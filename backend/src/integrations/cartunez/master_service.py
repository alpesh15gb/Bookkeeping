from __future__ import annotations

import time
import uuid
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError
from sqlalchemy.orm import Session

from src.integrations.cartunez.master_models import (
    MasterSyncAudit,
    SyncedCustomer,
    SyncedInventoryLevel,
    SyncedPrice,
    SyncedProduct,
    SyncedProductVariant,
)
from src.integrations.cartunez.master_schemas import (
    CustomerUpdatedRequest,
    InventoryUpdatedRequest,
    PriceUpdatedRequest,
    ProductChangedRequest,
    parse_utc,
)
from src.integrations.cartunez.outbound import CartunezOutboundDispatcher
from src.integrations.core.auth import AuthenticatedIntegrationRequest
from src.integrations.core.exceptions import ErrorDetail, IntegrationError
from src.integrations.core.idempotency import HandlerResult, IntegrationRequestProcessor, IntegrationResult
from src.integrations.core.models import IntegrationConnection, IntegrationEntityMap
from src.integrations.core.utils import generate_request_id, utc_now


SchemaT = TypeVar("SchemaT", bound=BaseModel)


class MasterDataNotFound(IntegrationError):
    status_code = 404
    code = "RESOURCE_NOT_FOUND"


class MasterDataConflict(IntegrationError):
    status_code = 409
    code = "BUSINESS_CONFLICT"


class MasterDataUnprocessable(IntegrationError):
    status_code = 422
    code = "BUSINESS_VALIDATION_FAILED"


class CartunezMasterDataService:
    integration_name = "cartunez"

    def __init__(self) -> None:
        self.processor = IntegrationRequestProcessor(self.integration_name)
        self.outbound = CartunezOutboundDispatcher()

    async def process_product(self, request, db: Session, external_id: str) -> IntegrationResult:
        return await self.processor.process(
            request, db, lambda session, auth: self._upsert_product(session, auth, external_id)
        )

    async def process_prices(self, request, db: Session, external_id: str) -> IntegrationResult:
        return await self.processor.process(
            request, db, lambda session, auth: self._replace_prices(session, auth, external_id)
        )

    async def process_inventory(self, request, db: Session, external_id: str) -> IntegrationResult:
        return await self.processor.process(
            request, db, lambda session, auth: self._replace_inventory(session, auth, external_id)
        )

    async def process_customer(self, request, db: Session, external_id: str) -> IntegrationResult:
        return await self.processor.process(
            request, db, lambda session, auth: self._upsert_customer(session, auth, external_id)
        )

    def _upsert_product(
        self, db: Session, auth: AuthenticatedIntegrationRequest, path_id: str
    ) -> HandlerResult:
        started = time.perf_counter()
        payload = self._validate(ProductChangedRequest, auth)
        product_data = payload.product
        self._validate_ids(path_id, product_data.apexbooks_product_id)
        self._serialize_tenant(db, auth)

        mapping = self._mapping(db, auth, "product", path_id)
        product = db.get(SyncedProduct, mapping.internal_id) if mapping else None
        created = mapping is None
        old_values = self._product_snapshot(product) if product else None
        if mapping is not None and product is None:
            raise MasterDataConflict("The product mapping points to a missing internal product.")
        if product is None:
            internal_id = uuid.uuid4()
            product = SyncedProduct(
                id=internal_id,
                tenant_id=auth.internal_tenant_id,
                apexbooks_product_id=path_id,
                medusa_product_id=self._public_id("prod", internal_id),
            )
            db.add(product)
            mapping = self._create_mapping(db, auth, "product", path_id, internal_id)

        product.title = product_data.title
        product.description = product_data.description
        product.categories = list(product_data.categories)
        product.images = list(product_data.images)
        product.active = product_data.active
        product.hsn_sac = product_data.hsn_sac
        product.gst_rate_bps = product_data.gst_rate_bps
        product.source_updated_at = parse_utc(product_data.updated_at)
        mapping.external_version = product_data.updated_at
        mapping.sync_status = "SYNCED"
        mapping.last_synced_at = utc_now()

        medusa_variant_ids: list[str] = []
        incoming_variant_ids = {item.apexbooks_variant_id for item in product_data.variants}
        for variant_data in product_data.variants:
            variant_map = self._mapping(db, auth, "variant", variant_data.apexbooks_variant_id)
            variant = db.get(SyncedProductVariant, variant_map.internal_id) if variant_map else None
            if variant_map is not None and variant is None:
                raise MasterDataConflict("A variant mapping points to a missing internal variant.")
            if variant is not None and variant.product_id != product.id:
                raise MasterDataConflict("A variant is already mapped to another product.")
            if variant is None:
                variant_id = uuid.uuid4()
                variant = SyncedProductVariant(
                    id=variant_id,
                    tenant_id=auth.internal_tenant_id,
                    product_id=product.id,
                    apexbooks_variant_id=variant_data.apexbooks_variant_id,
                    medusa_variant_id=self._public_id("variant", variant_id),
                )
                db.add(variant)
                variant_map = self._create_mapping(
                    db, auth, "variant", variant_data.apexbooks_variant_id, variant_id
                )
            variant.sku = variant_data.sku
            variant.title = variant_data.title
            variant.product_type = variant_data.product_type
            variant.active = variant_data.active
            variant_map.sync_status = "SYNCED"
            variant_map.last_synced_at = utc_now()
            medusa_variant_ids.append(variant.medusa_variant_id)

        for existing in list(product.variants):
            if existing.apexbooks_variant_id not in incoming_variant_ids:
                existing.active = False
                old_mapping = self._mapping(db, auth, "variant", existing.apexbooks_variant_id)
                if old_mapping:
                    old_mapping.sync_status = "DISABLED"

        db.flush()
        new_values = self._product_snapshot(product)
        self._audit(db, auth, "product", path_id, old_values, new_values, created, started)
        self.outbound.enqueue(db, auth.internal_tenant_id, payload.model_dump(mode="json"))
        return self._success(
            auth,
            201 if created else 200,
            {
                "apexbooks_product_id": path_id,
                "medusa_product_id": product.medusa_product_id,
                "medusa_variant_ids": medusa_variant_ids,
            },
        )

    def _replace_prices(
        self, db: Session, auth: AuthenticatedIntegrationRequest, path_id: str
    ) -> HandlerResult:
        started = time.perf_counter()
        payload = self._validate(PriceUpdatedRequest, auth)
        update = payload.price_update
        self._validate_ids(path_id, update.apexbooks_product_id)
        self._serialize_tenant(db, auth)
        product = self._mapped_product(db, auth, path_id)
        old_rows = db.query(SyncedPrice).filter(
            SyncedPrice.tenant_id == auth.internal_tenant_id,
            SyncedPrice.product_id == product.id,
        ).all()
        old_values = [self._price_snapshot(row) for row in old_rows]
        variant_by_external = self._variants(db, auth, product, [p.apexbooks_variant_id for p in update.prices])
        db.query(SyncedPrice).filter(
            SyncedPrice.tenant_id == auth.internal_tenant_id,
            SyncedPrice.product_id == product.id,
        ).delete(synchronize_session=False)
        new_values = []
        for item in update.prices:
            row = SyncedPrice(
                tenant_id=auth.internal_tenant_id,
                product_id=product.id,
                variant_id=variant_by_external[item.apexbooks_variant_id].id,
                amount_minor=item.amount_minor,
                currency_code=item.currency_code,
                tax_inclusive=item.tax_inclusive,
                price_list_id=item.price_list_id,
                valid_from=parse_utc(item.valid_from),
                valid_to=parse_utc(item.valid_to),
                source_updated_at=parse_utc(update.updated_at),
            )
            db.add(row)
            new_values.append(self._price_snapshot(row, item.apexbooks_variant_id))
        db.flush()
        self._audit(db, auth, "price", path_id, old_values, new_values, not old_rows, started)
        self.outbound.enqueue(db, auth.internal_tenant_id, payload.model_dump(mode="json"))
        return self._success(
            auth,
            201 if not old_rows else 200,
            {"apexbooks_product_id": path_id, "replaced_price_count": len(update.prices)},
        )

    def _replace_inventory(
        self, db: Session, auth: AuthenticatedIntegrationRequest, path_id: str
    ) -> HandlerResult:
        started = time.perf_counter()
        payload = self._validate(InventoryUpdatedRequest, auth)
        update = payload.inventory_update
        self._validate_ids(path_id, update.apexbooks_product_id)
        self._serialize_tenant(db, auth)
        product = self._mapped_product(db, auth, path_id)
        old_rows = db.query(SyncedInventoryLevel).filter(
            SyncedInventoryLevel.tenant_id == auth.internal_tenant_id,
            SyncedInventoryLevel.product_id == product.id,
        ).all()
        old_values = [self._inventory_snapshot(row) for row in old_rows]
        variant_by_external = self._variants(db, auth, product, [p.apexbooks_variant_id for p in update.levels])
        db.query(SyncedInventoryLevel).filter(
            SyncedInventoryLevel.tenant_id == auth.internal_tenant_id,
            SyncedInventoryLevel.product_id == product.id,
        ).delete(synchronize_session=False)
        new_values = []
        for item in update.levels:
            row = SyncedInventoryLevel(
                tenant_id=auth.internal_tenant_id,
                product_id=product.id,
                variant_id=variant_by_external[item.apexbooks_variant_id].id,
                warehouse_id=item.warehouse_id,
                available_quantity=item.available_quantity,
                reserved_quantity=item.reserved_quantity,
                source_updated_at=parse_utc(item.updated_at),
            )
            db.add(row)
            new_values.append(self._inventory_snapshot(row, item.apexbooks_variant_id))
        db.flush()
        self._audit(db, auth, "inventory", path_id, old_values, new_values, not old_rows, started)
        self.outbound.enqueue(db, auth.internal_tenant_id, payload.model_dump(mode="json"))
        return self._success(
            auth,
            201 if not old_rows else 200,
            {"apexbooks_product_id": path_id, "replaced_level_count": len(update.levels)},
        )

    def _upsert_customer(
        self, db: Session, auth: AuthenticatedIntegrationRequest, path_id: str
    ) -> HandlerResult:
        started = time.perf_counter()
        payload = self._validate(CustomerUpdatedRequest, auth)
        data = payload.customer
        self._validate_ids(path_id, data.apexbooks_customer_id)
        self._serialize_tenant(db, auth)
        mapping = self._mapping(db, auth, "customer", path_id)
        customer = db.get(SyncedCustomer, mapping.internal_id) if mapping else None
        created = mapping is None
        old_values = self._customer_snapshot(customer) if customer else None
        if mapping is not None and customer is None:
            raise MasterDataConflict("The customer mapping points to a missing internal customer.")
        medusa_owner = db.query(SyncedCustomer).filter(
            SyncedCustomer.tenant_id == auth.internal_tenant_id,
            SyncedCustomer.medusa_customer_id == data.medusa_customer_id,
        ).one_or_none()
        if medusa_owner is not None and (customer is None or medusa_owner.id != customer.id):
            raise MasterDataConflict("The Medusa customer ID is already mapped to another customer.")
        if customer is None:
            customer_id = uuid.uuid4()
            customer = SyncedCustomer(
                id=customer_id,
                tenant_id=auth.internal_tenant_id,
                apexbooks_customer_id=path_id,
            )
            db.add(customer)
            mapping = self._create_mapping(db, auth, "customer", path_id, customer_id)
        customer.medusa_customer_id = data.medusa_customer_id
        customer.first_name = data.first_name
        customer.last_name = data.last_name
        customer.phone = data.phone
        customer.accounting_email = data.accounting_email
        customer.gstin = data.gst.gstin
        customer.gst_type = data.gst.gst_type
        customer.billing_address = data.billing_address.model_dump()
        customer.shipping_address = data.shipping_address.model_dump()
        customer.state_code = data.gst.state_code
        customer.credit_terms_days = data.credit_terms_days
        customer.active = data.active
        customer.source_updated_at = parse_utc(data.updated_at)
        mapping.external_version = data.updated_at
        mapping.sync_status = "SYNCED"
        mapping.last_synced_at = utc_now()
        db.flush()
        new_values = self._customer_snapshot(customer)
        self._audit(db, auth, "customer", path_id, old_values, new_values, created, started)
        self.outbound.enqueue(db, auth.internal_tenant_id, payload.model_dump(mode="json"))
        return self._success(
            auth,
            201 if created else 200,
            {"apexbooks_customer_id": path_id, "medusa_customer_id": customer.medusa_customer_id},
        )

    @staticmethod
    def _validate(schema: type[SchemaT], auth: AuthenticatedIntegrationRequest) -> SchemaT:
        try:
            return schema.model_validate_json(auth.raw_body)
        except ValidationError as exc:
            details = [
                ErrorDetail("body", ".".join(str(part) for part in error["loc"]), error["msg"])
                for error in exc.errors(include_input=False)[:25]
            ]
            raise IntegrationError("The request body does not match the Contract v1 JSON Schema.", details) from exc

    @staticmethod
    def _validate_ids(path_id: str, body_id: str) -> None:
        if path_id != body_id:
            raise IntegrationError(
                "Path and entity identifiers must match.",
                [ErrorDetail("path", "entity_id", "Identifier does not match the event payload.")],
            )

    @staticmethod
    def _serialize_tenant(db: Session, auth: AuthenticatedIntegrationRequest) -> None:
        db.query(IntegrationConnection).filter(IntegrationConnection.id == auth.connection.id).with_for_update().one()

    def _mapping(self, db: Session, auth, entity_type: str, external_id: str):
        return db.query(IntegrationEntityMap).filter(
            IntegrationEntityMap.tenant_id == auth.internal_tenant_id,
            IntegrationEntityMap.integration_name == self.integration_name,
            IntegrationEntityMap.entity_type == entity_type,
            IntegrationEntityMap.external_id == external_id,
        ).with_for_update().one_or_none()

    def _create_mapping(self, db, auth, entity_type, external_id, internal_id):
        mapping = IntegrationEntityMap(
            tenant_id=auth.internal_tenant_id,
            integration_name=self.integration_name,
            entity_type=entity_type,
            external_id=external_id,
            internal_id=internal_id,
            sync_status="PENDING",
        )
        db.add(mapping)
        return mapping

    def _mapped_product(self, db, auth, external_id) -> SyncedProduct:
        mapping = self._mapping(db, auth, "product", external_id)
        if mapping is None or mapping.sync_status == "DISABLED":
            raise MasterDataNotFound("The ApexBooks product has not been synchronized.")
        product = db.get(SyncedProduct, mapping.internal_id)
        if product is None:
            raise MasterDataNotFound("The mapped product no longer exists.")
        return product

    def _variants(self, db, auth, product, external_ids):
        result = {}
        for external_id in set(external_ids):
            mapping = self._mapping(db, auth, "variant", external_id)
            variant = db.get(SyncedProductVariant, mapping.internal_id) if mapping else None
            if mapping is None or mapping.sync_status != "SYNCED" or variant is None or variant.product_id != product.id:
                raise MasterDataUnprocessable(
                    f"Variant {external_id} is not actively mapped to this product."
                )
            result[external_id] = variant
        return result

    @staticmethod
    def _success(auth, status_code: int, data: dict[str, Any]) -> HandlerResult:
        return HandlerResult(
            status_code=status_code,
            body={
                "success": True,
                "data": data,
                "meta": {
                    "request_id": generate_request_id(),
                    "event_id": auth.envelope.event_id,
                    "tenant_id": auth.external_tenant_id,
                    "version": "v1",
                    "idempotency_key": auth.envelope.idempotency_key,
                    "processed_at": utc_now().isoformat().replace("+00:00", "Z"),
                },
            },
        )

    def _audit(self, db, auth, entity_type, external_id, old, new, created, started):
        db.add(MasterSyncAudit(
            tenant_id=auth.internal_tenant_id,
            integration_name=self.integration_name,
            event_name=auth.envelope.event_name,
            event_id=auth.envelope.event_id,
            idempotency_key=auth.envelope.idempotency_key,
            entity_type=entity_type,
            external_id=external_id,
            old_values=old,
            new_values=new,
            processing_time_ms=max(0, round((time.perf_counter() - started) * 1000)),
            result="CREATED" if created else "UPDATED",
        ))

    @staticmethod
    def _public_id(prefix: str, value: uuid.UUID) -> str:
        return f"{prefix}_{value.hex.upper()[:26]}"

    @staticmethod
    def _product_snapshot(product):
        return {
            "title": product.title,
            "description": product.description,
            "categories": product.categories,
            "images": product.images,
            "active": product.active,
            "hsn_sac": product.hsn_sac,
            "gst_rate_bps": product.gst_rate_bps,
            "variants": [
                {
                    "apexbooks_variant_id": row.apexbooks_variant_id,
                    "medusa_variant_id": row.medusa_variant_id,
                    "sku": row.sku,
                    "title": row.title,
                    "product_type": row.product_type,
                    "active": row.active,
                }
                for row in product.variants
            ],
        }

    @staticmethod
    def _price_snapshot(row, apexbooks_variant_id=None):
        return {
            "apexbooks_variant_id": apexbooks_variant_id,
            "amount_minor": row.amount_minor,
            "currency_code": row.currency_code,
            "tax_inclusive": row.tax_inclusive,
            "price_list_id": row.price_list_id,
            "valid_from": row.valid_from.isoformat() if row.valid_from else None,
            "valid_to": row.valid_to.isoformat() if row.valid_to else None,
        }

    @staticmethod
    def _inventory_snapshot(row, apexbooks_variant_id=None):
        return {
            "apexbooks_variant_id": apexbooks_variant_id,
            "warehouse_id": row.warehouse_id,
            "available_quantity": row.available_quantity,
            "reserved_quantity": row.reserved_quantity,
            "updated_at": row.source_updated_at.isoformat() if row.source_updated_at else None,
        }

    @staticmethod
    def _customer_snapshot(customer):
        return {
            "medusa_customer_id": customer.medusa_customer_id,
            "first_name": customer.first_name,
            "last_name": customer.last_name,
            "phone": customer.phone,
            "accounting_email": customer.accounting_email,
            "gstin": customer.gstin,
            "gst_type": customer.gst_type,
            "billing_address": customer.billing_address,
            "shipping_address": customer.shipping_address,
            "state_code": customer.state_code,
            "credit_terms_days": customer.credit_terms_days,
            "active": customer.active,
        }
