from __future__ import annotations

import time
import uuid

from pydantic import ValidationError
from sqlalchemy import func
from sqlalchemy.orm import Session

from src.infrastructure.database.models import Contact
from src.integrations.cartunez.customer_schemas import CustomerCreatedRequest
from src.integrations.cartunez.master_models import MasterSyncAudit, SyncedCustomer
from src.integrations.core.auth import AuthenticatedIntegrationRequest
from src.integrations.core.exceptions import ErrorDetail, IntegrationError
from src.integrations.core.idempotency import HandlerResult, IntegrationRequestProcessor, IntegrationResult
from src.integrations.core.models import IntegrationConnection, IntegrationEntityMap
from src.integrations.core.utils import generate_request_id, utc_now


class CustomerLifecycleConflict(IntegrationError):
    status_code = 409
    code = "LIFECYCLE_CONFLICT"


class CartunezCustomerService:
    integration_name = "cartunez"

    def __init__(self) -> None:
        self.processor = IntegrationRequestProcessor(self.integration_name)

    async def process_create(self, request, db: Session) -> IntegrationResult:
        return await self.processor.process(request, db, self._upsert_customer)

    def _upsert_customer(
        self,
        db: Session,
        auth: AuthenticatedIntegrationRequest,
    ) -> HandlerResult:
        started = time.perf_counter()
        payload = self._validate(auth)
        data = payload.customer
        self._serialize_connection(db, auth)

        email = str(data.accounting_email).strip().lower()
        gstin = data.gst.gstin.strip().upper() if data.gst.gstin else None
        candidates: dict[uuid.UUID, tuple[Contact | None, SyncedCustomer | None]] = {}

        def add_candidate(contact: Contact | None, synced: SyncedCustomer | None) -> None:
            candidate_id = contact.id if contact is not None else synced.id if synced is not None else None
            if candidate_id is None:
                return
            old_contact, old_synced = candidates.get(candidate_id, (None, None))
            candidates[candidate_id] = (contact or old_contact, synced or old_synced)

        provided_mapping = None
        if data.apexbooks_customer_id is not None:
            provided_mapping = self._mapping(db, auth, data.apexbooks_customer_id)
            if provided_mapping is None:
                raise CustomerLifecycleConflict(
                    "The supplied ApexBooks customer ID is not mapped for this tenant."
                )
            add_candidate(
                db.get(Contact, provided_mapping.internal_id),
                db.get(SyncedCustomer, provided_mapping.internal_id),
            )

        medusa_match = db.query(SyncedCustomer).filter(
            SyncedCustomer.tenant_id == auth.internal_tenant_id,
            SyncedCustomer.medusa_customer_id == data.medusa_customer_id,
        ).with_for_update().one_or_none()
        if medusa_match is not None:
            add_candidate(db.get(Contact, medusa_match.id), medusa_match)

        if gstin is not None:
            for synced in db.query(SyncedCustomer).filter(
                SyncedCustomer.tenant_id == auth.internal_tenant_id,
                func.upper(SyncedCustomer.gstin) == gstin,
            ).with_for_update().all():
                add_candidate(db.get(Contact, synced.id), synced)
            for contact in db.query(Contact).filter(
                Contact.tenant_id == auth.internal_tenant_id,
                Contact.deleted_at.is_(None),
                func.upper(Contact.gstin) == gstin,
            ).with_for_update().all():
                add_candidate(contact, db.get(SyncedCustomer, contact.id))
        else:
            for synced in db.query(SyncedCustomer).filter(
                SyncedCustomer.tenant_id == auth.internal_tenant_id,
                SyncedCustomer.gstin.is_(None),
                func.lower(SyncedCustomer.accounting_email) == email,
            ).with_for_update().all():
                add_candidate(db.get(Contact, synced.id), synced)
            for contact in db.query(Contact).filter(
                Contact.tenant_id == auth.internal_tenant_id,
                Contact.deleted_at.is_(None),
                Contact.gstin.is_(None),
                func.lower(Contact.email) == email,
            ).with_for_update().all():
                add_candidate(contact, db.get(SyncedCustomer, contact.id))

        if len(candidates) > 1:
            raise CustomerLifecycleConflict(
                "Customer identifiers resolve to different ApexBooks customers."
            )

        contact: Contact | None
        synced: SyncedCustomer | None
        if candidates:
            contact, synced = next(iter(candidates.values()))
        else:
            contact, synced = None, None

        if synced is not None and synced.medusa_customer_id != data.medusa_customer_id:
            raise CustomerLifecycleConflict(
                "The ApexBooks customer is mapped to a different Medusa customer."
            )

        created = contact is None and synced is None
        customer_id = contact.id if contact is not None else synced.id if synced is not None else uuid.uuid4()
        apexbooks_customer_id = (
            synced.apexbooks_customer_id
            if synced is not None
            else data.apexbooks_customer_id or self._public_id(customer_id)
        )
        mapping = self._mapping(db, auth, apexbooks_customer_id)
        if mapping is not None and mapping.internal_id != customer_id:
            raise CustomerLifecycleConflict("The ApexBooks customer mapping is already in use.")
        if provided_mapping is not None and provided_mapping.internal_id != customer_id:
            raise CustomerLifecycleConflict("The supplied customer mapping conflicts with canonical identity.")

        old_values = self._snapshot(contact, synced) if not created else None
        address_billing = data.billing_address.model_dump(mode="json")
        address_shipping = data.shipping_address.model_dump(mode="json")
        now = utc_now()

        if contact is None:
            contact = Contact(
                id=customer_id,
                tenant_id=auth.internal_tenant_id,
                contact_type="CUSTOMER",
                opening_balance=0,
                credit_balance=0,
            )
            db.add(contact)
        contact.name = f"{data.first_name.strip()} {data.last_name.strip()}".strip()
        contact.email = email
        contact.phone = data.phone
        contact.gstin = gstin
        contact.registration_type = data.gst.gst_type
        contact.billing_address = address_billing
        contact.shipping_address = address_shipping
        contact.state_code = data.gst.state_code
        contact.is_active = True
        contact.deleted_at = None
        custom_fields = dict(contact.custom_fields or {})
        custom_fields["credit_terms_days"] = data.credit_terms_days
        custom_fields["apexbooks_customer_id"] = apexbooks_customer_id
        custom_fields["medusa_customer_id"] = data.medusa_customer_id
        contact.custom_fields = custom_fields

        if synced is None:
            synced = SyncedCustomer(
                id=customer_id,
                tenant_id=auth.internal_tenant_id,
                apexbooks_customer_id=apexbooks_customer_id,
                medusa_customer_id=data.medusa_customer_id,
            )
            db.add(synced)
        synced.medusa_customer_id = data.medusa_customer_id
        synced.apexbooks_customer_id = apexbooks_customer_id
        synced.first_name = data.first_name.strip()
        synced.last_name = data.last_name.strip()
        synced.phone = data.phone
        synced.accounting_email = email
        synced.gstin = gstin
        synced.gst_type = data.gst.gst_type
        synced.billing_address = address_billing
        synced.shipping_address = address_shipping
        synced.state_code = data.gst.state_code
        synced.credit_terms_days = data.credit_terms_days
        synced.active = True
        synced.source_updated_at = now

        if mapping is None:
            mapping = IntegrationEntityMap(
                tenant_id=auth.internal_tenant_id,
                integration_name=self.integration_name,
                entity_type="customer",
                external_id=apexbooks_customer_id,
                internal_id=customer_id,
            )
            db.add(mapping)
        mapping.sync_status = "SYNCED"
        mapping.external_version = payload.occurred_at
        mapping.last_synced_at = now

        db.flush()
        new_values = self._snapshot(contact, synced)
        db.add(MasterSyncAudit(
            tenant_id=auth.internal_tenant_id,
            integration_name=self.integration_name,
            event_name=payload.event_name,
            event_id=payload.event_id,
            idempotency_key=payload.idempotency_key,
            entity_type="customer",
            external_id=apexbooks_customer_id,
            old_values=old_values,
            new_values=new_values,
            processing_time_ms=max(0, round((time.perf_counter() - started) * 1000)),
            result="CREATED" if created else "UPDATED",
        ))

        canonical = {
            "apexbooks_customer_id": apexbooks_customer_id,
            "medusa_customer_id": synced.medusa_customer_id,
            "accounting_email": synced.accounting_email,
            "first_name": synced.first_name,
            "last_name": synced.last_name,
            "phone": synced.phone,
            "gst": {
                "gstin": synced.gstin,
                "gst_type": synced.gst_type,
                "state_code": synced.state_code,
            },
            "billing_address": synced.billing_address,
            "shipping_address": synced.shipping_address,
            "credit_terms_days": synced.credit_terms_days,
            "active": synced.active,
            "updated_at": now.isoformat().replace("+00:00", "Z"),
        }
        return HandlerResult(
            status_code=201 if created else 200,
            body={
                "success": True,
                "data": {"customer": canonical, "created": created},
                "meta": {
                    "request_id": generate_request_id(),
                    "event_id": payload.event_id,
                    "tenant_id": auth.external_tenant_id,
                    "version": "v1",
                    "idempotency_key": payload.idempotency_key,
                    "processed_at": now.isoformat().replace("+00:00", "Z"),
                },
            },
        )

    @staticmethod
    def _validate(auth: AuthenticatedIntegrationRequest) -> CustomerCreatedRequest:
        try:
            return CustomerCreatedRequest.model_validate_json(auth.raw_body)
        except ValidationError as exc:
            details = [
                ErrorDetail("body", ".".join(str(part) for part in error["loc"]), error["msg"])
                for error in exc.errors(include_input=False)[:25]
            ]
            raise IntegrationError(
                "The request body does not match the Contract v1 JSON Schema.", details
            ) from exc

    @staticmethod
    def _serialize_connection(db: Session, auth: AuthenticatedIntegrationRequest) -> None:
        db.query(IntegrationConnection).filter(
            IntegrationConnection.id == auth.connection.id
        ).with_for_update().one()

    def _mapping(self, db, auth, apexbooks_customer_id):
        return db.query(IntegrationEntityMap).filter(
            IntegrationEntityMap.tenant_id == auth.internal_tenant_id,
            IntegrationEntityMap.integration_name == self.integration_name,
            IntegrationEntityMap.entity_type == "customer",
            IntegrationEntityMap.external_id == apexbooks_customer_id,
        ).with_for_update().one_or_none()

    @staticmethod
    def _public_id(customer_id: uuid.UUID) -> str:
        return f"ab_customer_{customer_id.hex.upper()[:26]}"

    @staticmethod
    def _snapshot(contact: Contact | None, synced: SyncedCustomer | None) -> dict:
        return {
            "apexbooks_customer_id": synced.apexbooks_customer_id if synced else None,
            "medusa_customer_id": synced.medusa_customer_id if synced else None,
            "name": contact.name if contact else None,
            "accounting_email": synced.accounting_email if synced else contact.email if contact else None,
            "phone": synced.phone if synced else contact.phone if contact else None,
            "gstin": synced.gstin if synced else contact.gstin if contact else None,
            "gst_type": synced.gst_type if synced else contact.registration_type if contact else None,
            "billing_address": synced.billing_address if synced else contact.billing_address if contact else None,
            "shipping_address": synced.shipping_address if synced else contact.shipping_address if contact else None,
            "state_code": synced.state_code if synced else contact.state_code if contact else None,
            "credit_terms_days": synced.credit_terms_days if synced else (contact.custom_fields or {}).get("credit_terms_days") if contact else None,
            "active": synced.active if synced else contact.is_active if contact else None,
        }
