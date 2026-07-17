from __future__ import annotations

import time
import uuid
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError
from sqlalchemy.orm import Session

from src.infrastructure.database.models import SalesOrder, SalesOrderLine
from src.integrations.cartunez.master_models import (
    SyncedCustomer,
    SyncedInventoryLevel,
    SyncedPrice,
    SyncedProduct,
    SyncedProductVariant,
)
from src.integrations.cartunez.order_models import (
    IntegrationInventoryMovement,
    IntegrationOrderAudit,
    IntegrationOrderState,
)
from src.integrations.cartunez.order_schemas import (
    GstBreakdown,
    OrderCancelledRequest,
    OrderCreatedRequest,
    OrderSnapshot,
    OrderUpdatedRequest,
    parse_utc,
)
from src.integrations.core.auth import AuthenticatedIntegrationRequest
from src.integrations.core.exceptions import ErrorDetail, IntegrationError
from src.integrations.core.idempotency import HandlerResult, IntegrationRequestProcessor, IntegrationResult
from src.integrations.core.models import IntegrationConnection, IntegrationEntityMap
from src.integrations.core.utils import generate_request_id, utc_now


SchemaT = TypeVar("SchemaT", bound=BaseModel)


class OrderBusinessError(IntegrationError):
    def __init__(self, code: str, message: str, status_code: int, details=None):
        super().__init__(message, details)
        self.code = code
        self.status_code = status_code


class CartunezOrderService:
    integration_name = "cartunez"

    def __init__(self) -> None:
        self.processor = IntegrationRequestProcessor(self.integration_name)

    async def process_create(self, request, db: Session) -> IntegrationResult:
        return await self.processor.process(request, db, self._create)

    async def process_update(self, request, db: Session, external_order_id: str) -> IntegrationResult:
        return await self.processor.process(
            request, db, lambda session, auth: self._update(session, auth, external_order_id)
        )

    async def process_cancel(self, request, db: Session, external_order_id: str) -> IntegrationResult:
        return await self.processor.process(
            request, db, lambda session, auth: self._cancel(session, auth, external_order_id)
        )

    def _create(self, db: Session, auth: AuthenticatedIntegrationRequest) -> HandlerResult:
        started = time.perf_counter()
        event = self._validate(OrderCreatedRequest, auth)
        snapshot = event.order
        self._validate_identity(snapshot.medusa_order_id, auth.envelope.source_id)
        self._serialize_tenant(db, auth)
        if self._order_state(db, auth, snapshot.medusa_order_id) is not None:
            self._raise("LIFECYCLE_CONFLICT", "The Medusa order is already mapped.", 409)
        if snapshot.order_revision != 1:
            self._raise("LIFECYCLE_CONFLICT", "A newly created order must have revision 1.", 409)

        customer = self._resolve_customer(db, auth, snapshot)
        resolved_lines = self._validate_commercial_snapshot(db, auth, snapshot)
        sales_order_id = uuid.uuid4()
        apexbooks_order_id = self._public_id("ab_order", sales_order_id)
        accounting_reference = f"MEDUSA-{snapshot.display_id}"
        number_owner = db.query(SalesOrder).filter(
            SalesOrder.tenant_id == auth.internal_tenant_id,
            SalesOrder.so_number == accounting_reference,
        ).one_or_none()
        if number_owner is not None:
            self._raise("LIFECYCLE_CONFLICT", "The reserved accounting reference is already in use.", 409)

        sales_order = SalesOrder(
            id=sales_order_id,
            tenant_id=auth.internal_tenant_id,
            contact_id=None,
            so_number=accounting_reference,
            order_date=parse_utc(snapshot.placed_at).date(),
            due_date=parse_utc(snapshot.placed_at).date() + timedelta(days=snapshot.customer.credit_terms_days),
            status="DRAFT",
            subtotal=self._major(snapshot.totals.taxable_total.amount_minor),
            discount_total=self._major(snapshot.totals.discount_total.amount_minor),
            cgst_amount=self._major(sum(line.gst.cgst_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.cgst_amount_minor),
            sgst_amount=self._major(sum(line.gst.sgst_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.sgst_amount_minor),
            igst_amount=self._major(sum(line.gst.igst_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.igst_amount_minor),
            utgst_amount=Decimal("0"),
            cess_amount=self._major(sum(line.gst.cess_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.cess_amount_minor),
            total=self._major(snapshot.totals.grand_total.amount_minor),
            amount_advanced=Decimal("0"),
            pos_state_code=snapshot.place_of_supply_state_code,
        )
        state = IntegrationOrderState(
            id=uuid.uuid4(),
            tenant_id=auth.internal_tenant_id,
            sales_order_id=sales_order_id,
            medusa_order_id=snapshot.medusa_order_id,
            apexbooks_order_id=apexbooks_order_id,
            medusa_customer_id=customer.medusa_customer_id,
            apexbooks_customer_id=customer.apexbooks_customer_id,
            accounting_reference=accounting_reference,
            revision=1,
            status="DRAFT",
            commercial_snapshot=snapshot.model_dump(mode="json"),
        )
        db.add_all([sales_order, state])
        db.add(IntegrationEntityMap(
            tenant_id=auth.internal_tenant_id,
            integration_name=self.integration_name,
            entity_type="order",
            external_id=snapshot.medusa_order_id,
            internal_id=sales_order_id,
            external_version="1",
            sync_status="SYNCED",
            last_synced_at=utc_now(),
        ))
        db.flush()
        line_ids = self._replace_lines(db, auth, sales_order, snapshot, resolved_lines)
        self._reserve(db, auth, state, snapshot, resolved_lines, line_ids)
        db.flush()
        new_values = self._audit_snapshot(state, snapshot)
        self._audit(db, auth, state, snapshot, None, new_values, "CREATED", started)
        return self._success(auth, state, 201)

    def _update(
        self, db: Session, auth: AuthenticatedIntegrationRequest, external_order_id: str
    ) -> HandlerResult:
        started = time.perf_counter()
        event = self._validate(OrderUpdatedRequest, auth)
        snapshot = event.order
        self._validate_path_identity(external_order_id, snapshot.medusa_order_id, auth.envelope.source_id)
        self._serialize_tenant(db, auth)
        state = self._required_order_state(db, auth, external_order_id)
        sales_order = db.query(SalesOrder).filter(SalesOrder.id == state.sales_order_id).with_for_update().one_or_none()
        if sales_order is None:
            self._raise("RESOURCE_NOT_FOUND", "The mapped sales order does not exist.", 404)
        if state.status != "DRAFT" or sales_order.status != "DRAFT" or state.invoice_id is not None or sales_order.converted_to_invoice_id is not None or state.captured_amount_minor > 0:
            self._raise("ORDER_IMMUTABLE", "Only an uninvoiced, unpaid DRAFT order can be updated.", 409)
        if event.expected_order_revision != state.revision or snapshot.order_revision != event.expected_order_revision + 1:
            self._raise("LIFECYCLE_CONFLICT", "The order revision is stale or non-sequential.", 409)

        customer = self._resolve_customer(db, auth, snapshot)
        resolved_lines = self._validate_commercial_snapshot(db, auth, snapshot)
        old_values = self._audit_snapshot(state, None)
        self._release_reservations(db, auth, state)
        self._apply_sales_order(sales_order, snapshot)
        line_ids = self._replace_lines(db, auth, sales_order, snapshot, resolved_lines)
        self._reserve(db, auth, state, snapshot, resolved_lines, line_ids)
        state.medusa_customer_id = customer.medusa_customer_id
        state.apexbooks_customer_id = customer.apexbooks_customer_id
        state.revision = snapshot.order_revision
        state.commercial_snapshot = snapshot.model_dump(mode="json")
        mapping = self._mapping(db, auth, "order", external_order_id)
        mapping.external_version = str(state.revision)
        mapping.last_synced_at = utc_now()
        db.flush()
        new_values = self._audit_snapshot(state, snapshot)
        self._audit(db, auth, state, snapshot, old_values, new_values, "UPDATED", started)
        return self._success(auth, state, 200)

    def _cancel(
        self, db: Session, auth: AuthenticatedIntegrationRequest, external_order_id: str
    ) -> HandlerResult:
        started = time.perf_counter()
        event = self._validate(OrderCancelledRequest, auth)
        cancellation = event.cancellation
        self._validate_path_identity(external_order_id, cancellation.medusa_order_id, auth.envelope.source_id)
        self._serialize_tenant(db, auth)
        state = self._required_order_state(db, auth, external_order_id)
        sales_order = db.query(SalesOrder).filter(SalesOrder.id == state.sales_order_id).with_for_update().one_or_none()
        if sales_order is None:
            self._raise("RESOURCE_NOT_FOUND", "The mapped sales order does not exist.", 404)
        if cancellation.expected_order_revision != state.revision:
            self._raise("LIFECYCLE_CONFLICT", "The cancellation revision is stale.", 409)
        if state.invoice_id is not None or state.apexbooks_invoice_id is not None or sales_order.converted_to_invoice_id is not None or state.captured_amount_minor > state.refunded_amount_minor or state.status in {"PARTIALLY_PAID", "PAID"}:
            self._raise("REFUND_REQUIRED", "Paid or invoiced orders must be refunded through payment.refunded.", 409)
        if state.status != "DRAFT" or sales_order.status != "DRAFT":
            self._raise("LIFECYCLE_CONFLICT", "The order cannot be cancelled from its current state.", 409)

        old_values = self._audit_snapshot(state, None)
        self._release_reservations(db, auth, state)
        state.status = "CANCELLED"
        state.cancellation_reason_code = cancellation.reason_code
        state.cancellation_reason = cancellation.reason
        state.cancelled_at = parse_utc(cancellation.cancelled_at)
        sales_order.status = "CANCELLED"
        snapshot = OrderSnapshot.model_validate(state.commercial_snapshot)
        db.flush()
        new_values = self._audit_snapshot(state, snapshot)
        self._audit(db, auth, state, snapshot, old_values, new_values, "CANCELLED", started)
        return self._success(auth, state, 200)

    def _resolve_customer(self, db, auth, snapshot: OrderSnapshot) -> SyncedCustomer:
        customer = db.query(SyncedCustomer).filter(
            SyncedCustomer.tenant_id == auth.internal_tenant_id,
            SyncedCustomer.medusa_customer_id == snapshot.customer.medusa_customer_id,
        ).with_for_update().one_or_none()
        if customer is None or not customer.active:
            self._raise("RESOURCE_NOT_FOUND", "The order customer has no active mapping.", 404)
        if snapshot.customer.apexbooks_customer_id is not None and snapshot.customer.apexbooks_customer_id != customer.apexbooks_customer_id:
            self._raise("LIFECYCLE_CONFLICT", "Customer identifiers resolve to different customers.", 409)
        mapping = self._mapping(db, auth, "customer", customer.apexbooks_customer_id)
        if mapping is None or mapping.internal_id != customer.id or mapping.sync_status != "SYNCED":
            self._raise("RESOURCE_NOT_FOUND", "The ApexBooks customer mapping is unavailable.", 404)
        return customer

    def _validate_commercial_snapshot(self, db, auth, snapshot: OrderSnapshot):
        placed_at = parse_utc(snapshot.placed_at)
        resolved = {}
        for line in snapshot.lines:
            product_map = self._mapping(db, auth, "product", line.apexbooks_product_id)
            variant_map = self._mapping(db, auth, "variant", line.apexbooks_variant_id)
            product = db.get(SyncedProduct, product_map.internal_id) if product_map else None
            variant = db.get(SyncedProductVariant, variant_map.internal_id) if variant_map else None
            if (
                product_map is None or variant_map is None or product_map.sync_status != "SYNCED"
                or variant_map.sync_status != "SYNCED" or product is None or variant is None
                or not product.active or not variant.active or variant.product_id != product.id
            ):
                self._raise("RESOURCE_NOT_FOUND", f"Product or variant for line {line.medusa_line_id} is not actively mapped.", 404)
            if product.medusa_product_id != line.medusa_product_id or variant.medusa_variant_id != line.medusa_variant_id:
                self._raise("LIFECYCLE_CONFLICT", "Medusa and ApexBooks product mappings disagree.", 409)
            if variant.sku != line.sku or variant.product_type != line.product_type:
                self._raise("PRICE_MISMATCH", "Line SKU or product type does not match master data.", 422)
            if product.hsn_sac != line.gst.hsn_sac or product.gst_rate_bps != line.gst.gst_rate_bps:
                self._raise("GST_MISMATCH", "Line HSN/SAC or GST rate does not match master data.", 422)
            prices = db.query(SyncedPrice).filter(
                SyncedPrice.tenant_id == auth.internal_tenant_id,
                SyncedPrice.product_id == product.id,
                SyncedPrice.variant_id == variant.id,
            ).all()
            matching = [price for price in prices if self._price_matches(price, line, placed_at)]
            if not matching:
                self._raise("PRICE_MISMATCH", "No active authoritative price matches the order line.", 422)
            self._validate_line_math(line, snapshot)
            resolved[line.medusa_line_id] = (product, variant)
        self._validate_shipping_math(snapshot)
        self._validate_totals(snapshot)
        return resolved

    def _validate_line_math(self, line, snapshot):
        self._validate_currency(snapshot.currency_code, line.unit_price, line.discount, line.line_total)
        gross = line.unit_price.amount_minor * line.quantity
        self._validate_gst_math(
            gross, line.discount.amount_minor, line.tax_inclusive, line.gst,
            line.line_total.amount_minor, snapshot.seller_state_code, snapshot.place_of_supply_state_code,
        )

    def _validate_shipping_math(self, snapshot):
        shipping = snapshot.shipping
        self._validate_currency(snapshot.currency_code, shipping.unit_price, shipping.discount, shipping.line_total)
        self._validate_gst_math(
            shipping.unit_price.amount_minor, shipping.discount.amount_minor, shipping.tax_inclusive,
            shipping.gst, shipping.line_total.amount_minor,
            snapshot.seller_state_code, snapshot.place_of_supply_state_code,
        )

    def _validate_gst_math(self, gross, discount, tax_inclusive, gst: GstBreakdown, line_total, seller_state, place_state):
        if discount > gross or gst.discount_minor != discount:
            self._raise("GST_MISMATCH", "Discount arithmetic does not reconcile.", 422)
        intrastate = seller_state == place_state
        if intrastate:
            if gst.igst_rate_bps or gst.igst_amount_minor or gst.cgst_rate_bps + gst.sgst_rate_bps != gst.gst_rate_bps:
                self._raise("GST_MISMATCH", "Intrastate GST components are invalid.", 422)
        elif gst.cgst_rate_bps or gst.sgst_rate_bps or gst.cgst_amount_minor or gst.sgst_amount_minor or gst.igst_rate_bps != gst.gst_rate_bps:
            self._raise("GST_MISMATCH", "Interstate GST components are invalid.", 422)
        discounted = gross - discount
        divisor = 10000 + gst.gst_rate_bps + gst.cess_rate_bps
        taxable = self._round_minor(Decimal(discounted) * Decimal(10000) / Decimal(divisor)) if tax_inclusive else discounted
        components = {
            "cgst": self._round_minor(Decimal(taxable) * Decimal(gst.cgst_rate_bps) / Decimal(10000)),
            "sgst": self._round_minor(Decimal(taxable) * Decimal(gst.sgst_rate_bps) / Decimal(10000)),
            "igst": self._round_minor(Decimal(taxable) * Decimal(gst.igst_rate_bps) / Decimal(10000)),
            "cess": self._round_minor(Decimal(taxable) * Decimal(gst.cess_rate_bps) / Decimal(10000)),
        }
        tax = sum(components.values())
        if (
            gst.taxable_value_minor != taxable or gst.cgst_amount_minor != components["cgst"]
            or gst.sgst_amount_minor != components["sgst"] or gst.igst_amount_minor != components["igst"]
            or gst.cess_amount_minor != components["cess"] or gst.tax_amount_minor != tax
            or line_total != taxable + tax
        ):
            self._raise("GST_MISMATCH", "GST amounts or line total do not reconcile.", 422)

    def _validate_totals(self, snapshot):
        monies = list(snapshot.totals.model_dump().values())
        if any(value["currency_code"] != snapshot.currency_code for value in monies):
            self._raise("PRICE_MISMATCH", "Order total currencies must match the order currency.", 422)
        items_gross = sum(line.unit_price.amount_minor * line.quantity for line in snapshot.lines)
        discount = sum(line.discount.amount_minor for line in snapshot.lines) + snapshot.shipping.discount.amount_minor
        taxable = sum(line.gst.taxable_value_minor for line in snapshot.lines) + snapshot.shipping.gst.taxable_value_minor
        tax = sum(line.gst.tax_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.tax_amount_minor
        shipping = snapshot.shipping.line_total.amount_minor
        grand = sum(line.line_total.amount_minor for line in snapshot.lines) + shipping
        expected = (items_gross, discount, taxable, tax, shipping, grand)
        actual = (
            snapshot.totals.items_gross.amount_minor, snapshot.totals.discount_total.amount_minor,
            snapshot.totals.taxable_total.amount_minor, snapshot.totals.tax_total.amount_minor,
            snapshot.totals.shipping_total.amount_minor, snapshot.totals.grand_total.amount_minor,
        )
        if actual != expected:
            self._raise("GST_MISMATCH", "Order totals do not reconcile with line and shipping totals.", 422)

    def _replace_lines(self, db, auth, sales_order, snapshot, resolved):
        existing_mappings = {
            row.external_id: row for row in db.query(IntegrationEntityMap).filter(
                IntegrationEntityMap.tenant_id == auth.internal_tenant_id,
                IntegrationEntityMap.integration_name == self.integration_name,
                IntegrationEntityMap.entity_type == "order_line",
            ).all()
        }
        db.query(SalesOrderLine).filter(SalesOrderLine.sales_order_id == sales_order.id).delete(synchronize_session=False)
        incoming = set()
        line_ids = {}
        for line in snapshot.lines:
            incoming.add(line.medusa_line_id)
            line_id = uuid.uuid4()
            line_ids[line.medusa_line_id] = line_id
            db.add(SalesOrderLine(
                id=line_id,
                sales_order_id=sales_order.id,
                product_id=None,
                description=line.title,
                quantity=Decimal(line.quantity),
                rate=self._major(line.unit_price.amount_minor),
                discount=self._major(line.discount.amount_minor),
                subtotal=self._major(line.gst.taxable_value_minor),
                hsn_sac=line.gst.hsn_sac,
                gst_rate=Decimal(line.gst.gst_rate_bps) / Decimal(100),
                cgst_rate=Decimal(line.gst.cgst_rate_bps) / Decimal(100),
                cgst_amount=self._major(line.gst.cgst_amount_minor),
                sgst_rate=Decimal(line.gst.sgst_rate_bps) / Decimal(100),
                sgst_amount=self._major(line.gst.sgst_amount_minor),
                igst_rate=Decimal(line.gst.igst_rate_bps) / Decimal(100),
                igst_amount=self._major(line.gst.igst_amount_minor),
                utgst_rate=Decimal("0"), utgst_amount=Decimal("0"),
                cess_rate=Decimal(line.gst.cess_rate_bps) / Decimal(100),
                cess_amount=self._major(line.gst.cess_amount_minor),
                total=self._major(line.line_total.amount_minor),
            ))
            mapping = existing_mappings.get(line.medusa_line_id)
            if mapping is None:
                mapping = IntegrationEntityMap(
                    tenant_id=auth.internal_tenant_id, integration_name=self.integration_name,
                    entity_type="order_line", external_id=line.medusa_line_id,
                )
                db.add(mapping)
            mapping.internal_id = line_id
            mapping.external_version = str(snapshot.order_revision)
            mapping.sync_status = "SYNCED"
            mapping.last_synced_at = utc_now()
        for external_id, mapping in existing_mappings.items():
            if external_id not in incoming and mapping.internal_id in {
                row[0] for row in db.query(IntegrationInventoryMovement.sales_order_line_id).filter(
                    IntegrationInventoryMovement.order_state_id == self._state_id_for_sales_order(db, sales_order.id)
                ).all()
            }:
                mapping.sync_status = "DISABLED"
        db.flush()
        return line_ids

    def _reserve(self, db, auth, state, snapshot, resolved, line_ids):
        for line in snapshot.lines:
            _, variant = resolved[line.medusa_line_id]
            if line.product_type == "SERVICE":
                continue
            remaining = line.quantity
            levels = db.query(SyncedInventoryLevel).filter(
                SyncedInventoryLevel.tenant_id == auth.internal_tenant_id,
                SyncedInventoryLevel.product_id == resolved[line.medusa_line_id][0].id,
                SyncedInventoryLevel.variant_id == variant.id,
            ).order_by(SyncedInventoryLevel.warehouse_id).with_for_update().all()
            for level in levels:
                capacity = max(0, level.available_quantity - level.reserved_quantity)
                allocated = min(remaining, capacity)
                if allocated:
                    level.reserved_quantity += allocated
                    db.add(IntegrationInventoryMovement(
                        tenant_id=auth.internal_tenant_id, order_state_id=state.id,
                        sales_order_line_id=line_ids[line.medusa_line_id], variant_id=variant.id,
                        warehouse_id=level.warehouse_id, movement_type="RESERVATION",
                        quantity_delta=allocated, event_id=auth.envelope.event_id,
                    ))
                    remaining -= allocated
                if remaining == 0:
                    break
            if remaining:
                self._raise("INVENTORY_REJECTED", f"Insufficient unreserved inventory for SKU {line.sku}.", 422)

    def _release_reservations(self, db, auth, state):
        movements = db.query(IntegrationInventoryMovement).filter(
            IntegrationInventoryMovement.tenant_id == auth.internal_tenant_id,
            IntegrationInventoryMovement.order_state_id == state.id,
        ).all()
        balances = {}
        line_ids = {}
        for movement in movements:
            key = (movement.variant_id, movement.warehouse_id)
            balances[key] = balances.get(key, 0) + movement.quantity_delta
            line_ids[key] = movement.sales_order_line_id
        for (variant_id, warehouse_id), quantity in balances.items():
            if quantity <= 0:
                continue
            level = db.query(SyncedInventoryLevel).filter(
                SyncedInventoryLevel.tenant_id == auth.internal_tenant_id,
                SyncedInventoryLevel.variant_id == variant_id,
                SyncedInventoryLevel.warehouse_id == warehouse_id,
            ).with_for_update().one_or_none()
            if level is None or level.reserved_quantity < quantity:
                self._raise("INVENTORY_REJECTED", "Stored reservation state is inconsistent.", 422)
            level.reserved_quantity -= quantity
            db.add(IntegrationInventoryMovement(
                tenant_id=auth.internal_tenant_id, order_state_id=state.id,
                sales_order_line_id=line_ids[(variant_id, warehouse_id)], variant_id=variant_id,
                warehouse_id=warehouse_id, movement_type="RESERVATION_RELEASE",
                quantity_delta=-quantity, event_id=auth.envelope.event_id,
            ))

    @staticmethod
    def _apply_sales_order(order, snapshot):
        order.order_date = parse_utc(snapshot.placed_at).date()
        order.due_date = order.order_date + timedelta(days=snapshot.customer.credit_terms_days)
        order.subtotal = CartunezOrderService._major(snapshot.totals.taxable_total.amount_minor)
        order.discount_total = CartunezOrderService._major(snapshot.totals.discount_total.amount_minor)
        order.cgst_amount = CartunezOrderService._major(sum(line.gst.cgst_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.cgst_amount_minor)
        order.sgst_amount = CartunezOrderService._major(sum(line.gst.sgst_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.sgst_amount_minor)
        order.igst_amount = CartunezOrderService._major(sum(line.gst.igst_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.igst_amount_minor)
        order.cess_amount = CartunezOrderService._major(sum(line.gst.cess_amount_minor for line in snapshot.lines) + snapshot.shipping.gst.cess_amount_minor)
        order.total = CartunezOrderService._major(snapshot.totals.grand_total.amount_minor)
        order.pos_state_code = snapshot.place_of_supply_state_code

    @staticmethod
    def _price_matches(price, line, placed_at):
        def aware(value):
            if value is None:
                return None
            return value.replace(tzinfo=placed_at.tzinfo) if value.tzinfo is None else value
        valid_from, valid_to = aware(price.valid_from), aware(price.valid_to)
        return (
            price.currency_code == line.unit_price.currency_code
            and price.amount_minor == line.unit_price.amount_minor
            and price.tax_inclusive == line.tax_inclusive
            and (valid_from is None or valid_from <= placed_at)
            and (valid_to is None or placed_at < valid_to)
        )

    @staticmethod
    def _validate_currency(currency, *monies):
        if any(money.currency_code != currency for money in monies):
            CartunezOrderService._raise("PRICE_MISMATCH", "All order money must use the order currency.", 422)

    def _order_state(self, db, auth, external_id):
        return db.query(IntegrationOrderState).filter(
            IntegrationOrderState.tenant_id == auth.internal_tenant_id,
            IntegrationOrderState.medusa_order_id == external_id,
        ).with_for_update().one_or_none()

    def _required_order_state(self, db, auth, external_id):
        mapping = self._mapping(db, auth, "order", external_id)
        state = self._order_state(db, auth, external_id)
        if mapping is None or mapping.sync_status != "SYNCED" or state is None or mapping.internal_id != state.sales_order_id:
            self._raise("RESOURCE_NOT_FOUND", "The Medusa order mapping does not exist.", 404)
        return state

    def _mapping(self, db, auth, entity_type, external_id):
        return db.query(IntegrationEntityMap).filter(
            IntegrationEntityMap.tenant_id == auth.internal_tenant_id,
            IntegrationEntityMap.integration_name == self.integration_name,
            IntegrationEntityMap.entity_type == entity_type,
            IntegrationEntityMap.external_id == external_id,
        ).with_for_update().one_or_none()

    @staticmethod
    def _state_id_for_sales_order(db, sales_order_id):
        value = db.query(IntegrationOrderState.id).filter(IntegrationOrderState.sales_order_id == sales_order_id).scalar()
        return value

    @staticmethod
    def _serialize_tenant(db, auth):
        db.query(IntegrationConnection).filter(IntegrationConnection.id == auth.connection.id).with_for_update().one()

    @staticmethod
    def _validate(schema: type[SchemaT], auth) -> SchemaT:
        try:
            return schema.model_validate_json(auth.raw_body)
        except ValidationError as exc:
            details = [ErrorDetail("body", ".".join(str(p) for p in e["loc"]), e["msg"]) for e in exc.errors(include_input=False)[:25]]
            raise IntegrationError("The request body does not match the Contract v1 JSON Schema.", details) from exc

    @staticmethod
    def _validate_identity(body_id, source_id):
        if body_id != source_id:
            raise IntegrationError("Order source ID must match the order identifier.")

    @staticmethod
    def _validate_path_identity(path_id, body_id, source_id):
        if path_id != body_id or body_id != source_id:
            raise IntegrationError("Path, source, and order identifiers must match.")

    @staticmethod
    def _success(auth, state, status_code):
        return HandlerResult(status_code=status_code, body={
            "success": True,
            "data": {
                "apexbooks_order_id": state.apexbooks_order_id,
                "apexbooks_customer_id": state.apexbooks_customer_id,
                "apexbooks_invoice_id": state.apexbooks_invoice_id,
                "order_status": state.status,
                "order_revision": state.revision,
            },
            "meta": {
                "request_id": generate_request_id(), "event_id": auth.envelope.event_id,
                "tenant_id": auth.external_tenant_id, "version": "v1",
                "idempotency_key": auth.envelope.idempotency_key,
                "processed_at": utc_now().isoformat().replace("+00:00", "Z"),
            },
        })

    def _audit(self, db, auth, state, snapshot, old, new, result, started):
        db.add(IntegrationOrderAudit(
            tenant_id=auth.internal_tenant_id, event_name=auth.envelope.event_name,
            event_id=auth.envelope.event_id, idempotency_key=auth.envelope.idempotency_key,
            medusa_order_id=state.medusa_order_id, apexbooks_order_id=state.apexbooks_order_id,
            medusa_customer_id=state.medusa_customer_id, apexbooks_customer_id=state.apexbooks_customer_id,
            product_ids=[line.apexbooks_product_id for line in snapshot.lines],
            old_values=old, new_values=new,
            execution_time_ms=max(0, round((time.perf_counter() - started) * 1000)), result=result,
        ))

    @staticmethod
    def _audit_snapshot(state, snapshot):
        commercial = snapshot.model_dump(mode="json") if snapshot is not None else state.commercial_snapshot
        return {
            "status": state.status, "revision": state.revision,
            "invoice_id": state.apexbooks_invoice_id,
            "captured_amount_minor": state.captured_amount_minor,
            "commercial_snapshot": commercial,
        }

    @staticmethod
    def _public_id(prefix, value):
        return f"{prefix}_{value.hex.upper()[:26]}"

    @staticmethod
    def _major(value):
        return Decimal(value) / Decimal(100)

    @staticmethod
    def _round_minor(value):
        return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))

    @staticmethod
    def _raise(code, message, status_code):
        raise OrderBusinessError(code, message, status_code)
