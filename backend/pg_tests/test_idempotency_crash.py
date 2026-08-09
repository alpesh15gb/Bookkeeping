"""Priority 3 — Financial idempotency survives process-crash/retry scenarios."""

import threading
import uuid
from datetime import date
from decimal import Decimal

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import Invoice

from seed import (
    TENANT_A,
    seed_contact,
    seed_tenants,
)


@pytest.fixture()
def app_env(pg, db_admin):
    """A minimal FastAPI app wired to PostgreSQL with the real middleware."""
    import src.api.idempotency_middleware as middleware_mod
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy.pool import NullPool

    seed_tenants(db_admin)
    contact = seed_contact(db_admin, TENANT_A, "Cust A")
    db_admin.commit()

    engine = __import__("sqlalchemy").create_engine(pg["api_url"], poolclass=NullPool)
    Session = sessionmaker(bind=engine, autoflush=False)

    # Point the middleware at the PostgreSQL session factory (it imports
    # SessionLocal from src.core.database by default).
    middleware_mod.SessionLocal = Session

    app = FastAPI()
    app.add_middleware(middleware_mod.IdempotencyMiddleware)

    @app.post("/tx")
    def tx(payload: dict):
        db = Session()
        try:
            invoice = Invoice(
                tenant_id=TENANT_A,
                contact_id=contact.id,
                invoice_number=payload["number"],
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
            db.add(invoice)
            db.commit()
            return {"id": str(invoice.id), "number": invoice.invoice_number}
        finally:
            db.close()

    client = TestClient(app)
    yield {"client": client, "session_factory": Session, "engine": engine, "contact": contact}
    engine.dispose()


def _count_invoices(db) -> int:
    return db.execute(
        text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
        {"t": str(TENANT_A)},
    ).scalar()


def test_same_key_same_payload_replays(app_env, db_admin):
    client = app_env["client"]
    key = str(uuid.uuid4())
    headers = {"X-Tenant-ID": str(TENANT_A), "Idempotency-Key": key}

    first = client.post("/tx", json={"number": "IDEM-1"}, headers=headers)
    assert first.status_code == 200
    second = client.post("/tx", json={"number": "IDEM-1"}, headers=headers)
    assert second.status_code == 200
    assert second.headers.get("Idempotency-Replayed") == "true"
    assert second.json()["id"] == first.json()["id"]
    assert _count_invoices(db_admin) == 1


def test_same_key_different_payload_rejected(app_env, db_admin):
    client = app_env["client"]
    key = str(uuid.uuid4())
    headers = {"X-Tenant-ID": str(TENANT_A), "Idempotency-Key": key}

    first = client.post("/tx", json={"number": "IDEM-2"}, headers=headers)
    assert first.status_code == 200
    retry = client.post("/tx", json={"number": "DIFFERENT"}, headers=headers)
    assert retry.status_code == 422
    assert _count_invoices(db_admin) == 1


def test_crash_after_commit_before_response_no_duplicate(app_env, db_admin):
    """Simulate: business transaction commits, process dies before storing the
    response.  A retry must replay, never re-execute."""
    import hashlib
    import json as _json

    client = app_env["client"]
    session_factory = app_env["session_factory"]
    key = str(uuid.uuid4())
    body_hash = hashlib.sha256(_json.dumps({"number": "IDEM-CRASH-1"}).encode()).hexdigest()

    # --- Phase 1: claim the idempotency record like the middleware does ---
    claim_db = session_factory()
    claim_db.execute(
        text(
            "INSERT INTO idempotency_keys "
            "(id, idempotency_key, tenant_id, method, path, request_hash, status, is_processed, created_at) "
            "VALUES (:id, :key, :tenant, 'POST', '/tx', :hash, 'PROCESSING', false, CURRENT_TIMESTAMP)"
        ),
        {
            "id": str(uuid.uuid4()),
            "key": key,
            "tenant": str(TENANT_A),
            "hash": body_hash,
        },
    )
    claim_db.commit()
    claim_db.close()

    # --- Phase 2: run the business transaction with the inflight claim set,
    # exactly like the middleware does before the endpoint commits ---
    from src.core.idempotency import clear_inflight_claim, set_inflight_claim

    token = set_inflight_claim({"key": key, "tenant": str(TENANT_A), "method": "POST", "path": "/tx"})
    business_db = session_factory()
    try:
        set_tenant(business_db, TENANT_A)
        business_db.add(Invoice(
            tenant_id=TENANT_A,
            contact_id=app_env["contact"].id,
            invoice_number="IDEM-CRASH-1",
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
        ))
        business_db.commit()
        # The marker is now atomic with the financial commit.
        status = business_db.execute(
            text("SELECT status FROM idempotency_keys WHERE idempotency_key = :key"),
            {"key": key},
        ).scalar()
        assert status == "COMMITTED"
    finally:
        clear_inflight_claim(token)
        business_db.rollback()
        business_db.close()

    # Simulate process death: the response is NEVER stored.  Row is COMMITTED.
    # --- Phase 3: client retries the same key ---
    assert _count_invoices(db_admin) == 1
    headers = {"X-Tenant-ID": str(TENANT_A), "Idempotency-Key": key}
    retry = client.post("/tx", json={"number": "IDEM-CRASH-1"}, headers=headers)
    assert retry.status_code == 200
    assert retry.headers.get("Idempotency-Replayed") == "true"
    # No duplicate invoice despite the crash.
    assert _count_invoices(db_admin) == 1


def test_abandoned_processing_claim_before_commit_can_retry(app_env, db_admin):
    """A PROCESSING claim that never committed (crash before commit) is safe
    to reclaim after the stale threshold."""
    client = app_env["client"]
    session_factory = app_env["session_factory"]
    key = str(uuid.uuid4())

    claim_db = session_factory()
    claim_db.execute(
        text(
            "INSERT INTO idempotency_keys "
            "(id, idempotency_key, tenant_id, method, path, request_hash, status, is_processed, created_at) "
            "VALUES (:id, :key, :tenant, 'POST', '/tx', :hash, 'PROCESSING', false, "
            "CURRENT_TIMESTAMP - INTERVAL '10 minutes')"
        ),
        {
            "id": str(uuid.uuid4()),
            "key": key,
            "tenant": str(TENANT_A),
            "hash": "b" * 64,
        },
    )
    claim_db.commit()
    claim_db.close()

    headers = {"X-Tenant-ID": str(TENANT_A), "Idempotency-Key": key}
    resp = client.post("/tx", json={"number": "IDEM-STALE-1"}, headers=headers)
    assert resp.status_code == 200
    assert _count_invoices(db_admin) == 1


def test_concurrent_duplicate_requests_one_wins(app_env, db_admin):
    client = app_env["client"]
    key = str(uuid.uuid4())
    headers = {"X-Tenant-ID": str(TENANT_A), "Idempotency-Key": key}

    barrier = threading.Barrier(4)
    statuses = []
    lock = threading.Lock()

    def fire():
        barrier.wait(timeout=10)
        resp = client.post("/tx", json={"number": "IDEM-CONC-1"}, headers=headers)
        with lock:
            statuses.append(resp.status_code)

    threads = [threading.Thread(target=fire) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)

    assert 200 in statuses
    # 409 while another request still holds the claim; never 2 successful
    # executions with the same key.
    assert statuses.count(200) == 1
    assert _count_invoices(db_admin) == 1
