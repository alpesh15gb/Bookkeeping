"""Direct Edit/Delete idempotency behavior on real PostgreSQL."""

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool

from conftest import set_tenant
from seed import TENANT_A, seed_contact, seed_tenants
from src.core.idempotency import clear_inflight_claim, set_inflight_claim
from src.infrastructure.database.models import Invoice


def _invoice(tenant_id, contact_id, number):
    return Invoice(
        tenant_id=tenant_id,
        contact_id=contact_id,
        invoice_number=number,
        issue_date=date.today(),
        due_date=date.today(),
        status="POSTED",
        subtotal=Decimal("0.0000"),
        cgst_amount=Decimal("0.0000"),
        sgst_amount=Decimal("0.0000"),
        igst_amount=Decimal("0.0000"),
        utgst_amount=Decimal("0.0000"),
        cess_amount=Decimal("0.0000"),
        round_off=Decimal("0.0000"),
        shipping_charges=Decimal("0.0000"),
        total=Decimal("0.0000"),
        amount_paid=Decimal("0.0000"),
        e_invoice_status="PENDING",
        pos_state_code="27",
        currency="INR",
        exchange_rate=Decimal("1.000000"),
    )


def test_intermediate_flush_does_not_steal_replacement_replay_resource(pg, db_admin):
    seed_tenants(db_admin)
    contact = seed_contact(db_admin, TENANT_A, "Correction Idempotency Customer")
    db_admin.commit()

    engine = create_engine(pg["api_url"], poolclass=NullPool)
    Session = sessionmaker(bind=engine, autoflush=False)
    key = str(uuid.uuid4())
    path = f"/api/v1/invoices/{uuid.uuid4()}"

    claim_db = Session()
    try:
        set_tenant(claim_db, TENANT_A)
        claim_db.execute(
            text(
                "INSERT INTO idempotency_keys "
                "(id, idempotency_key, tenant_id, method, path, request_hash, "
                " status, is_processed, created_at) "
                "VALUES (:id, :key, :tenant, 'PUT', :path, :hash, "
                " 'PROCESSING', false, CURRENT_TIMESTAMP)"
            ),
            {
                "id": str(uuid.uuid4()),
                "key": key,
                "tenant": str(TENANT_A),
                "path": path,
                "hash": "c" * 64,
            },
        )
        claim_db.commit()
    finally:
        claim_db.close()

    token = set_inflight_claim(
        {"key": key, "tenant": str(TENANT_A), "method": "PUT", "path": path}
    )
    business = Session()
    replacement_id = None
    intermediate_id = None
    try:
        set_tenant(business, TENANT_A)

        # Simulate a correction's internal reversal/new accounting object.
        # Direct handlers explicitly defer the idempotency COMMITTED marker at
        # this point because the user-visible replacement does not exist yet.
        business.info["_defer_idempotency_mark"] = True
        intermediate = _invoice(TENANT_A, contact.id, f"INTERMEDIATE-{uuid.uuid4().hex[:8]}")
        business.add(intermediate)
        business.flush()
        intermediate_id = intermediate.id

        status = business.execute(
            text(
                "SELECT status FROM idempotency_keys "
                "WHERE idempotency_key=:key AND tenant_id=:tenant"
            ),
            {"key": key, "tenant": str(TENANT_A)},
        ).scalar()
        assert status == "PROCESSING"

        replacement = _invoice(TENANT_A, contact.id, f"REPLACEMENT-{uuid.uuid4().hex[:8]}")
        business.add(replacement)
        business.info["_idempotency_resource"] = replacement
        business.info.pop("_defer_idempotency_mark", None)
        business.flush()
        replacement_id = replacement.id
        business.commit()
    finally:
        clear_inflight_claim(token)
        business.rollback()
        business.close()

    row = db_admin.execute(
        text(
            "SELECT status, resource_type, resource_id FROM idempotency_keys "
            "WHERE idempotency_key=:key AND tenant_id=:tenant"
        ),
        {"key": key, "tenant": str(TENANT_A)},
    ).mappings().one()
    assert row["status"] == "COMMITTED"
    assert row["resource_type"] == "Invoice"
    assert row["resource_id"] == replacement_id
    assert row["resource_id"] != intermediate_id

    engine.dispose()
