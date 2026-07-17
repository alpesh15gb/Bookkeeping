from __future__ import annotations

import asyncio
import copy
import json
from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

from src.core.database import Base
from src.infrastructure.database.models import Invoice, JournalEntry, Payment, SalesOrder
from src.integrations.cartunez.master_models import SyncedInventoryLevel
from src.integrations.cartunez.order_service import CartunezOrderService
from src.integrations.cartunez.payment_models import (
    IntegrationPaymentAudit,
    IntegrationPaymentInventoryMovement,
    IntegrationPaymentState,
)
from src.integrations.cartunez.payment_service import CartunezPaymentService
from src.integrations.cartunez.tests.test_order_lifecycle import (
    API_KEY,
    ORDER,
    SECRET,
    TENANT,
    created_payload,
    execute as execute_order,
    seed,
)
from src.integrations.core.signatures import create_signature


PAYMENT = "pay_01ARZ3NDEKTSV4RRFFQ69G5FB5"
PATH = "/api/integrations/medusa/v1/payments/captured"


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def payment_payload(order_id=ORDER):
    return {
        "event_id": "evt_01ARZ3NDEKTSV4RRFFQ69G5FB4",
        "event_name": "payment.captured",
        "event_version": "v1",
        "tenant_id": TENANT,
        "occurred_at": now(),
        "source_system": "MEDUSA",
        "source_id": PAYMENT,
        "idempotency_key": f"{TENANT}:payment.captured:{PAYMENT}:v1",
        "payment": {
            "medusa_payment_id": PAYMENT,
            "medusa_order_id": order_id,
            "capture_sequence": 1,
            "amount": {"currency_code": "INR", "amount_minor": 118000},
            "provider_id": "razorpay",
            "transaction_id": "pay_RZP20260717A001",
            "captured_at": now(),
        },
    }


def make_request(payload, signature=None):
    raw = json.dumps(payload, separators=(",", ":")).encode()
    timestamp = now()
    signature = signature or create_signature(SECRET, timestamp, "POST", PATH, raw)
    headers = {
        "content-type": "application/json", "x-api-key": API_KEY, "x-tenant-id": TENANT,
        "x-event-id": payload["event_id"], "x-idempotency-key": payload["idempotency_key"],
        "x-timestamp": timestamp, "x-signature": signature,
    }
    delivered = False

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.disconnect"}
        delivered = True
        return {"type": "http.request", "body": raw, "more_body": False}

    return Request({
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "POST",
        "scheme": "https", "path": PATH, "raw_path": PATH.encode(), "query_string": b"",
        "headers": [(key.encode(), value.encode()) for key, value in headers.items()],
        "client": ("127.0.0.1", 50000), "server": ("testserver", 443),
    }, receive)


def capture(service, db, payload, signature=None):
    return asyncio.run(service.process_capture(make_request(payload, signature), db))


@pytest.fixture
def database(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'payments.db'}", connect_args={"check_same_thread": False, "timeout": 10})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = factory(); seed(db)
    yield db
    db.close(); engine.dispose()


def create_order(db):
    result = execute_order(CartunezOrderService(), db, "create", created_payload())
    assert result.status_code == 201


def test_payment_capture_creates_invoice_receipt_and_sale_out(database):
    db = database; create_order(db)
    result = capture(CartunezPaymentService(), db, payment_payload())
    assert result.status_code == 201 and result.body["data"]["invoice_status"] == "PAID"
    assert db.query(Invoice).one().status == "PAID"
    assert db.query(Payment).count() == 1 and db.query(JournalEntry).count() == 2
    assert db.query(IntegrationPaymentInventoryMovement).one().quantity == 1
    level = db.query(SyncedInventoryLevel).one()
    assert level.available_quantity == 23 and level.reserved_quantity == 2
    assert db.query(SalesOrder).one().converted_to_invoice_id is not None
    assert db.query(IntegrationPaymentAudit).one().result == "CAPTURED"


def test_duplicate_payment_event_returns_cached_response(database):
    db = database; create_order(db); service = CartunezPaymentService(); payload = payment_payload()
    first = capture(service, db, payload); second = capture(service, db, payload)
    assert first.status_code == 201 and second.status_code == 200
    assert second.headers["Idempotency-Replayed"] == "true"
    assert db.query(IntegrationPaymentState).count() == 1 and db.query(Payment).count() == 1


def test_payment_for_unknown_order(database):
    db = database
    result = capture(CartunezPaymentService(), db, payment_payload("order_01ARZ3NDEKTSV4RRFFQ69G5FQQ"))
    assert result.status_code == 404 and result.body["error"]["code"] == "RESOURCE_NOT_FOUND"
    assert db.query(Payment).count() == 0


def test_invalid_signature(database):
    db = database; create_order(db)
    result = capture(CartunezPaymentService(), db, payment_payload(), "sha256=" + "0" * 64)
    assert result.status_code == 403 and result.body["error"]["code"] == "SIGNATURE_INVALID"
    assert db.query(Payment).count() == 0


def test_payment_replay_attempt(database):
    db = database; create_order(db); service = CartunezPaymentService(); payload = payment_payload()
    capture(service, db, payload)
    changed = copy.deepcopy(payload); changed["payment"]["transaction_id"] = "pay_CHANGED"
    result = capture(service, db, changed)
    assert result.status_code == 409 and result.body["error"]["code"] == "REPLAY_DETECTED"
    assert db.query(Payment).count() == 1


def test_sequential_partial_captures_reuse_invoice(database):
    db = database; create_order(db); service = CartunezPaymentService()
    first = payment_payload(); first["payment"]["amount"]["amount_minor"] = 60000
    first_result = capture(service, db, first)
    second = payment_payload()
    second_payment = "pay_01ARZ3NDEKTSV4RRFFQ69G5FC6"
    second["event_id"] = "evt_01ARZ3NDEKTSV4RRFFQ69G5FC7"
    second["source_id"] = second_payment
    second["idempotency_key"] = f"{TENANT}:payment.captured:{second_payment}:v1"
    second["payment"]["medusa_payment_id"] = second_payment
    second["payment"]["capture_sequence"] = 2
    second["payment"]["amount"]["amount_minor"] = 58000
    second["payment"]["transaction_id"] = "pay_RZP20260717A002"
    second_result = capture(service, db, second)
    assert first_result.body["data"]["invoice_status"] == "PARTIALLY_PAID"
    assert second_result.body["data"]["invoice_status"] == "PAID"
    assert db.query(Invoice).count() == 1 and db.query(Payment).count() == 2
    assert db.query(IntegrationPaymentInventoryMovement).count() == 1
