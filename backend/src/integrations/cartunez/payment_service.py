from __future__ import annotations

import time
import uuid
from decimal import Decimal

from pydantic import ValidationError
from sqlalchemy import func
from sqlalchemy.orm import Session

from src.domains.accounting.auto_post import auto_post_invoice
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, commit_ledger_draft
from src.infrastructure.database.models import (
    Contact,
    Invoice,
    InvoiceLine,
    Payment,
    PaymentAllocation,
    Product,
    SalesOrder,
)
from src.integrations.cartunez.master_models import (
    SyncedCustomer,
    SyncedInventoryLevel,
    SyncedProduct,
    SyncedProductVariant,
)
from src.integrations.cartunez.order_models import IntegrationInventoryMovement, IntegrationOrderState
from src.integrations.cartunez.payment_models import (
    IntegrationInvoiceLineMap,
    IntegrationPaymentAudit,
    IntegrationPaymentInventoryMovement,
    IntegrationPaymentState,
)
from src.integrations.cartunez.payment_schemas import PaymentCapturedRequest, parse_utc
from src.integrations.core.exceptions import ErrorDetail, IntegrationError
from src.integrations.core.idempotency import HandlerResult, IntegrationRequestProcessor, IntegrationResult
from src.integrations.core.models import IntegrationConnection, IntegrationEntityMap
from src.integrations.core.utils import generate_request_id, utc_now


class PaymentBusinessError(IntegrationError):
    def __init__(self, code: str, message: str, status_code: int):
        super().__init__(message)
        self.code = code
        self.status_code = status_code


class CartunezPaymentService:
    integration_name = "cartunez"

    def __init__(self) -> None:
        self.processor = IntegrationRequestProcessor(self.integration_name)

    async def process_capture(self, request, db: Session) -> IntegrationResult:
        return await self.processor.process(request, db, self._capture)

    def _capture(self, db: Session, auth) -> HandlerResult:
        started = time.perf_counter()
        event = self._validate(auth)
        payment = event.payment
        if payment.medusa_payment_id != auth.envelope.source_id:
            raise IntegrationError("Payment source ID must match medusa_payment_id.")
        if payment.amount.amount_minor <= 0:
            self._raise("LIFECYCLE_CONFLICT", "Captured amount must be greater than zero.", 422)
        self._serialize_tenant(db, auth)

        order_state = db.query(IntegrationOrderState).filter(
            IntegrationOrderState.tenant_id == auth.internal_tenant_id,
            IntegrationOrderState.medusa_order_id == payment.medusa_order_id,
        ).with_for_update().one_or_none()
        if order_state is None:
            self._raise("RESOURCE_NOT_FOUND", "The payment order does not exist.", 404)
        order_mapping = self._mapping(db, auth, "order", payment.medusa_order_id)
        if order_mapping is None or order_mapping.internal_id != order_state.sales_order_id:
            self._raise("RESOURCE_NOT_FOUND", "The payment order mapping is unavailable.", 404)
        if order_state.status == "CANCELLED":
            self._raise("LIFECYCLE_CONFLICT", "A cancelled order cannot accept payment.", 409)

        snapshot = order_state.commercial_snapshot
        if payment.amount.currency_code != snapshot["currency_code"]:
            self._raise("PRICE_MISMATCH", "Payment currency does not match the order.", 422)
        maximum_sequence = db.query(func.max(IntegrationPaymentState.capture_sequence)).filter(
            IntegrationPaymentState.tenant_id == auth.internal_tenant_id,
            IntegrationPaymentState.order_state_id == order_state.id,
        ).scalar() or 0
        if payment.capture_sequence != maximum_sequence + 1:
            self._raise("LIFECYCLE_CONFLICT", "Capture sequence must be new and contiguous.", 409)
        existing_payment = db.query(IntegrationPaymentState).filter(
            IntegrationPaymentState.tenant_id == auth.internal_tenant_id,
            IntegrationPaymentState.medusa_payment_id == payment.medusa_payment_id,
        ).one_or_none()
        if existing_payment is not None:
            self._raise("LIFECYCLE_CONFLICT", "The Medusa payment is already mapped.", 409)
        grand_total = snapshot["totals"]["grand_total"]["amount_minor"]
        new_captured = order_state.captured_amount_minor + payment.amount.amount_minor
        if new_captured > grand_total:
            self._raise("LIFECYCLE_CONFLICT", "Cumulative captures exceed the order total.", 422)

        old_values = {
            "captured_amount_minor": order_state.captured_amount_minor,
            "order_status": order_state.status,
            "invoice_id": order_state.apexbooks_invoice_id,
        }
        first_capture = order_state.invoice_id is None
        if first_capture:
            invoice = self._create_and_post_invoice(db, auth, order_state, snapshot)
        else:
            invoice = db.query(Invoice).filter(
                Invoice.id == order_state.invoice_id,
                Invoice.tenant_id == auth.internal_tenant_id,
            ).with_for_update().one_or_none()
            if invoice is None:
                self._raise("RESOURCE_NOT_FOUND", "The mapped invoice does not exist.", 404)

        payment_id = uuid.uuid4()
        apexbooks_payment_id = self._public_id("ab_payment", payment_id)
        receipt_id = self._public_id("ab_receipt", uuid.uuid4())
        payment_row = Payment(
            id=payment_id,
            tenant_id=auth.internal_tenant_id,
            contact_id=invoice.contact_id,
            payment_number=f"MEDPAY-{payment.medusa_payment_id[4:]}",
            payment_date=parse_utc(payment.captured_at).date(),
            payment_mode=self._payment_mode(payment.provider_id),
            amount=self._major(payment.amount.amount_minor),
            reference_number=payment.transaction_id[:50],
            description=f"Medusa capture via {payment.provider_id}",
            status="ACTIVE",
        )
        db.add(payment_row)
        db.flush()
        db.add(PaymentAllocation(
            payment_id=payment_id,
            invoice_id=invoice.id,
            amount=self._major(payment.amount.amount_minor),
        ))

        payment_state = IntegrationPaymentState(
            tenant_id=auth.internal_tenant_id,
            order_state_id=order_state.id,
            payment_id=payment_id,
            medusa_payment_id=payment.medusa_payment_id,
            apexbooks_payment_id=apexbooks_payment_id,
            receipt_id=receipt_id,
            capture_sequence=payment.capture_sequence,
            currency_code=payment.amount.currency_code,
            amount_minor=payment.amount.amount_minor,
            provider_id=payment.provider_id,
            transaction_id=payment.transaction_id,
            captured_at=parse_utc(payment.captured_at),
        )
        db.add(payment_state)
        db.add(IntegrationEntityMap(
            tenant_id=auth.internal_tenant_id,
            integration_name=self.integration_name,
            entity_type="payment",
            external_id=payment.medusa_payment_id,
            internal_id=payment_id,
            external_version=str(payment.capture_sequence),
            sync_status="SYNCED",
            last_synced_at=utc_now(),
        ))
        db.flush()

        if first_capture:
            self._convert_reservations_to_sale(db, auth, order_state, payment_state)

        invoice.amount_paid = self._major(new_captured)
        invoice.status = "PAID" if new_captured == grand_total else "PARTIALLY_PAID"
        order_state.captured_amount_minor = new_captured
        order_state.status = "PAID" if new_captured == grand_total else "PARTIALLY_PAID"
        sales_order = db.query(SalesOrder).filter(SalesOrder.id == order_state.sales_order_id).with_for_update().one()
        sales_order.amount_advanced = self._major(new_captured)

        self._post_receipt_journal(db, auth.internal_tenant_id, payment_row, invoice.contact_id, payment.provider_id)
        new_values = {
            "captured_amount_minor": new_captured,
            "order_status": order_state.status,
            "invoice_id": order_state.apexbooks_invoice_id,
            "invoice_status": invoice.status,
        }
        db.add(IntegrationPaymentAudit(
            tenant_id=auth.internal_tenant_id,
            event_id=auth.envelope.event_id,
            idempotency_key=auth.envelope.idempotency_key,
            medusa_payment_id=payment.medusa_payment_id,
            medusa_order_id=payment.medusa_order_id,
            apexbooks_payment_id=apexbooks_payment_id,
            apexbooks_invoice_id=order_state.apexbooks_invoice_id,
            capture_sequence=payment.capture_sequence,
            amount_minor=payment.amount.amount_minor,
            old_values=old_values,
            new_values=new_values,
            execution_time_ms=max(0, round((time.perf_counter() - started) * 1000)),
            result="CAPTURED",
        ))
        db.flush()
        return self._success(auth, payment_state, order_state, invoice)

    def _create_and_post_invoice(self, db, auth, order_state, snapshot) -> Invoice:
        customer = db.query(SyncedCustomer).filter(
            SyncedCustomer.tenant_id == auth.internal_tenant_id,
            SyncedCustomer.apexbooks_customer_id == order_state.apexbooks_customer_id,
        ).one_or_none()
        if customer is None:
            self._raise("RESOURCE_NOT_FOUND", "The mapped accounting customer does not exist.", 404)
        contact = self._materialize_contact(db, customer)
        placed_at = parse_utc(snapshot["placed_at"])
        invoice_id = uuid.uuid4()
        invoice_public_id = self._public_id("ab_invoice", invoice_id)
        total_minor = snapshot["totals"]["grand_total"]["amount_minor"]
        tax_minor = snapshot["totals"]["tax_total"]["amount_minor"]
        shipping_taxable = snapshot["shipping"]["gst"]["taxable_value_minor"]
        discount_minor = snapshot["totals"]["discount_total"]["amount_minor"]
        subtotal_minor = total_minor - tax_minor - shipping_taxable + discount_minor
        invoice = Invoice(
            id=invoice_id,
            tenant_id=auth.internal_tenant_id,
            contact_id=contact.id,
            source_document_type="SALES_ORDER",
            source_document_id=order_state.sales_order_id,
            invoice_number=f"MEDINV-{snapshot['display_id']}",
            issue_date=placed_at.date(),
            due_date=placed_at.date(),
            status="DRAFT",
            subtotal=self._major(subtotal_minor),
            discount_total=self._major(discount_minor),
            cgst_amount=self._major(sum(line["gst"]["cgst_amount_minor"] for line in snapshot["lines"]) + snapshot["shipping"]["gst"]["cgst_amount_minor"]),
            sgst_amount=self._major(sum(line["gst"]["sgst_amount_minor"] for line in snapshot["lines"]) + snapshot["shipping"]["gst"]["sgst_amount_minor"]),
            igst_amount=self._major(sum(line["gst"]["igst_amount_minor"] for line in snapshot["lines"]) + snapshot["shipping"]["gst"]["igst_amount_minor"]),
            utgst_amount=Decimal("0"),
            cess_amount=self._major(sum(line["gst"]["cess_amount_minor"] for line in snapshot["lines"]) + snapshot["shipping"]["gst"]["cess_amount_minor"]),
            round_off=Decimal("0"),
            shipping_charges=self._major(shipping_taxable),
            total=self._major(total_minor),
            amount_paid=Decimal("0"),
            pos_state_code=snapshot["place_of_supply_state_code"],
            reference_number=order_state.accounting_reference,
            is_gst_inclusive=any(line["tax_inclusive"] for line in snapshot["lines"]),
            currency=snapshot["currency_code"],
        )
        db.add(invoice)
        for line in snapshot["lines"]:
            variant = db.query(SyncedProductVariant).filter(
                SyncedProductVariant.tenant_id == auth.internal_tenant_id,
                SyncedProductVariant.apexbooks_variant_id == line["apexbooks_variant_id"],
            ).one_or_none()
            product = db.query(SyncedProduct).filter(
                SyncedProduct.tenant_id == auth.internal_tenant_id,
                SyncedProduct.apexbooks_product_id == line["apexbooks_product_id"],
            ).one_or_none()
            if variant is None or product is None:
                self._raise("RESOURCE_NOT_FOUND", "An invoiced product mapping is missing.", 404)
            accounting_product = self._materialize_product(db, auth.internal_tenant_id, product, variant, line)
            line_id = uuid.uuid4()
            invoice_line = InvoiceLine(
                id=line_id,
                invoice_id=invoice_id,
                product_id=accounting_product.id,
                description=line["title"][:255],
                quantity=Decimal(line["quantity"]),
                rate=self._major(line["unit_price"]["amount_minor"]),
                discount=self._major(line["discount"]["amount_minor"]),
                subtotal=self._major(line["gst"]["taxable_value_minor"] + line["discount"]["amount_minor"]),
                hsn_sac=line["gst"]["hsn_sac"],
                gst_rate=Decimal(line["gst"]["gst_rate_bps"]) / Decimal(100),
                cgst_rate=Decimal(line["gst"]["cgst_rate_bps"]) / Decimal(100),
                cgst_amount=self._major(line["gst"]["cgst_amount_minor"]),
                sgst_rate=Decimal(line["gst"]["sgst_rate_bps"]) / Decimal(100),
                sgst_amount=self._major(line["gst"]["sgst_amount_minor"]),
                igst_rate=Decimal(line["gst"]["igst_rate_bps"]) / Decimal(100),
                igst_amount=self._major(line["gst"]["igst_amount_minor"]),
                utgst_rate=Decimal("0"), utgst_amount=Decimal("0"),
                cess_rate=Decimal(line["gst"]["cess_rate_bps"]) / Decimal(100),
                cess_amount=self._major(line["gst"]["cess_amount_minor"]),
                total=self._major(line["line_total"]["amount_minor"]),
            )
            db.add(invoice_line)
            invoice_line_public_id = self._public_id("ab_invoiceline", line_id)
            db.add(IntegrationInvoiceLineMap(
                tenant_id=auth.internal_tenant_id,
                invoice_id=invoice_id,
                invoice_line_id=line_id,
                medusa_line_id=line["medusa_line_id"],
                apexbooks_invoice_line_id=invoice_line_public_id,
            ))
            db.add(IntegrationEntityMap(
                tenant_id=auth.internal_tenant_id,
                integration_name=self.integration_name,
                entity_type="invoice_line",
                external_id=invoice_line_public_id,
                internal_id=line_id,
                sync_status="SYNCED",
                last_synced_at=utc_now(),
            ))
        db.flush()
        auto_post_invoice(db, auth.internal_tenant_id, invoice, move_stock=False)
        order_state.invoice_id = invoice_id
        order_state.apexbooks_invoice_id = invoice_public_id
        sales_order = db.query(SalesOrder).filter(SalesOrder.id == order_state.sales_order_id).with_for_update().one()
        sales_order.contact_id = contact.id
        sales_order.converted_to_invoice_id = invoice_id
        sales_order.status = "CONFIRMED"
        db.add(IntegrationEntityMap(
            tenant_id=auth.internal_tenant_id,
            integration_name=self.integration_name,
            entity_type="invoice",
            external_id=invoice_public_id,
            internal_id=invoice_id,
            sync_status="SYNCED",
            last_synced_at=utc_now(),
        ))
        return invoice

    def _convert_reservations_to_sale(self, db, auth, order_state, payment_state):
        rows = db.query(
            IntegrationInventoryMovement.variant_id,
            IntegrationInventoryMovement.warehouse_id,
            func.sum(IntegrationInventoryMovement.quantity_delta),
        ).filter(
            IntegrationInventoryMovement.tenant_id == auth.internal_tenant_id,
            IntegrationInventoryMovement.order_state_id == order_state.id,
        ).group_by(
            IntegrationInventoryMovement.variant_id,
            IntegrationInventoryMovement.warehouse_id,
        ).all()
        for variant_id, warehouse_id, quantity in rows:
            quantity = int(quantity or 0)
            if quantity <= 0:
                continue
            level = db.query(SyncedInventoryLevel).filter(
                SyncedInventoryLevel.tenant_id == auth.internal_tenant_id,
                SyncedInventoryLevel.variant_id == variant_id,
                SyncedInventoryLevel.warehouse_id == warehouse_id,
            ).with_for_update().one_or_none()
            if level is None or level.reserved_quantity < quantity or level.available_quantity < quantity:
                self._raise("INVENTORY_REJECTED", "Reserved inventory is no longer available for sale.", 422)
            available_before, reserved_before = level.available_quantity, level.reserved_quantity
            level.available_quantity -= quantity
            level.reserved_quantity -= quantity
            db.add(IntegrationPaymentInventoryMovement(
                tenant_id=auth.internal_tenant_id,
                order_state_id=order_state.id,
                payment_state_id=payment_state.id,
                variant_id=variant_id,
                warehouse_id=warehouse_id,
                quantity=quantity,
                available_before=available_before,
                available_after=level.available_quantity,
                reserved_before=reserved_before,
                reserved_after=level.reserved_quantity,
            ))
            product = db.get(Product, variant_id)
            if product is not None:
                product.current_stock = (product.current_stock or Decimal("0")) - Decimal(quantity)

    @staticmethod
    def _materialize_contact(db, customer):
        contact = db.get(Contact, customer.id)
        if contact is None:
            contact = Contact(
                id=customer.id,
                tenant_id=customer.tenant_id,
                name=f"{customer.first_name} {customer.last_name}".strip(),
                email=customer.accounting_email,
                phone=customer.phone,
                contact_type="CUSTOMER",
                gstin=customer.gstin,
                registration_type=customer.gst_type,
                billing_address=customer.billing_address,
                shipping_address=customer.shipping_address,
                state_code=customer.state_code,
                is_active=customer.active,
            )
            db.add(contact)
            db.flush()
        return contact

    @staticmethod
    def _materialize_product(db, tenant_id, product, variant, line):
        accounting_product = db.get(Product, variant.id)
        if accounting_product is None:
            stock = db.query(func.coalesce(func.sum(SyncedInventoryLevel.available_quantity), 0)).filter(
                SyncedInventoryLevel.tenant_id == tenant_id,
                SyncedInventoryLevel.variant_id == variant.id,
            ).scalar()
            accounting_product = Product(
                id=variant.id,
                tenant_id=tenant_id,
                name=line["title"][:150],
                sku=variant.sku[:50],
                hsn_sac=product.hsn_sac,
                product_type=variant.product_type,
                uom="PCS" if variant.product_type == "GOODS" else "HRS",
                sales_price=CartunezPaymentService._major(line["unit_price"]["amount_minor"]),
                purchase_price=Decimal("0"),
                gst_rate=Decimal(product.gst_rate_bps) / Decimal(100),
                opening_stock=Decimal(stock),
                current_stock=Decimal(stock),
                reorder_level=Decimal("0"),
                is_active=variant.active,
            )
            db.add(accounting_product)
            db.flush()
        return accounting_product

    @staticmethod
    def _post_receipt_journal(db, tenant_id, payment, contact_id, provider_id):
        resolver = AccountResolver(db, tenant_id)
        asset_key = "assets.upi" if "upi" in provider_id.lower() else "assets.pos"
        draft = LedgerPostingEngine.create_payment_receipt_posting(
            tenant_id=tenant_id,
            payment_id=payment.id,
            payment_number=payment.payment_number,
            payment_date=payment.payment_date,
            bank_or_cash_account_id=resolver.resolve(asset_key),
            customer_account_id=resolver.resolve(f"customer.{contact_id}"),
            amount=payment.amount,
        )
        commit_ledger_draft(db, tenant_id, draft)

    def _mapping(self, db, auth, entity_type, external_id):
        return db.query(IntegrationEntityMap).filter(
            IntegrationEntityMap.tenant_id == auth.internal_tenant_id,
            IntegrationEntityMap.integration_name == self.integration_name,
            IntegrationEntityMap.entity_type == entity_type,
            IntegrationEntityMap.external_id == external_id,
            IntegrationEntityMap.sync_status == "SYNCED",
        ).one_or_none()

    @staticmethod
    def _serialize_tenant(db, auth):
        db.query(IntegrationConnection).filter(IntegrationConnection.id == auth.connection.id).with_for_update().one()

    @staticmethod
    def _validate(auth):
        try:
            return PaymentCapturedRequest.model_validate_json(auth.raw_body)
        except ValidationError as exc:
            details = [
                ErrorDetail("body", ".".join(str(part) for part in error["loc"]), error["msg"])
                for error in exc.errors(include_input=False)[:25]
            ]
            raise IntegrationError("The request body does not match PaymentCapturedRequest v1.", details) from exc

    @staticmethod
    def _success(auth, payment_state, order_state, invoice):
        return HandlerResult(status_code=201, body={
            "success": True,
            "data": {
                "apexbooks_payment_id": payment_state.apexbooks_payment_id,
                "receipt_id": payment_state.receipt_id,
                "apexbooks_invoice_id": order_state.apexbooks_invoice_id,
                "invoice_status": invoice.status,
                "amount_applied": {
                    "currency_code": payment_state.currency_code,
                    "amount_minor": payment_state.amount_minor,
                },
            },
            "meta": {
                "request_id": generate_request_id(),
                "event_id": auth.envelope.event_id,
                "tenant_id": auth.external_tenant_id,
                "version": "v1",
                "idempotency_key": auth.envelope.idempotency_key,
                "processed_at": utc_now().isoformat().replace("+00:00", "Z"),
            },
        })

    @staticmethod
    def _payment_mode(provider_id):
        return "UPI" if "upi" in provider_id.lower() else "POS"

    @staticmethod
    def _public_id(prefix, value):
        return f"{prefix}_{value.hex.upper()[:26]}"

    @staticmethod
    def _major(value):
        return Decimal(value) / Decimal(100)

    @staticmethod
    def _raise(code, message, status_code):
        raise PaymentBusinessError(code, message, status_code)
