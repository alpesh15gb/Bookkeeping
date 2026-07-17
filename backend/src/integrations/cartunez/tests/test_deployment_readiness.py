from __future__ import annotations

import asyncio
import json
import uuid
from datetime import date, datetime, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

from src.core.config import settings
from src.core.database import Base
from src.infrastructure.database.models import Contact, Tenant, WebhookEvent
from src.integrations.cartunez.customer_service import CartunezCustomerService
from src.integrations.cartunez.outbound import CartunezOutboundDispatcher
from src.integrations.core.models import IntegrationConnection, IntegrationEventLog
from src.integrations.core.signatures import create_signature
from src.main import REQUIRED_SCHEMA_REVISION, app


API_KEY = "ctz_live_7f91f651f6f64564a588a347a7f56c8e"
MEDUSA_API_KEY = "medusa_live_7f91f651f6f64564a588a347a7f56c"
SECRET = "cartunez-test-hmac-secret-at-least-32-bytes"
TENANT = "tenant_cartunez_in"
CUSTOMER_PATH = "/api/integrations/medusa/v1/customers"
MEDUSA_CUSTOMER = "cus_01ARZ3NDEKTSV4RRFFQ69G5FAX"


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


@pytest.fixture
def database(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'deployment-readiness.db'}",
        connect_args={"check_same_thread": False},
    )
    factory = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    Base.metadata.create_all(engine)
    db = factory()
    tenant = Tenant(
        id=uuid.uuid4(),
        legal_name="Deployment Readiness Test",
        trade_name="Readiness",
        financial_year_start=date.today(),
    )
    db.add(tenant)
    connection = IntegrationConnection(
        tenant_id=tenant.id,
        integration_name="cartunez",
        external_tenant_id=TENANT,
        api_key_prefix="pending",
        api_key_hash="pending",
        hmac_secret_encrypted="pending",
        status="ENABLED",
    )
    connection.set_api_key(API_KEY)
    connection.set_hmac_secret(SECRET)
    db.add(connection)
    db.commit()
    yield db, tenant, connection
    db.close()
    engine.dispose()


def customer_payload(event_id="evt_01ARZ3NDEKTSV4RRFFQ69G5FBC"):
    address = {
        "name": "Amit Sharma",
        "company": "Amit Auto Works",
        "phone": "+919999999999",
        "address_1": "24 Linking Road",
        "address_2": "Bandra West",
        "city": "Mumbai",
        "state": "Maharashtra",
        "state_code": "27",
        "postal_code": "400050",
        "country_code": "IN",
    }
    return {
        "event_id": event_id,
        "event_name": "customer.created",
        "event_version": "v1",
        "tenant_id": TENANT,
        "occurred_at": now(),
        "source_system": "MEDUSA",
        "source_id": MEDUSA_CUSTOMER,
        "idempotency_key": f"{TENANT}:customer.created:{MEDUSA_CUSTOMER}:v1",
        "customer": {
            "medusa_customer_id": MEDUSA_CUSTOMER,
            "apexbooks_customer_id": None,
            "accounting_email": "Amit.Sharma@cartunez.in",
            "first_name": "Amit",
            "last_name": "Sharma",
            "phone": "+919999999999",
            "gst": {"gstin": "27ABCDE1234F1Z5", "gst_type": "REGULAR", "state_code": "27"},
            "billing_address": address,
            "shipping_address": dict(address),
            "credit_terms_days": 15,
        },
    }


def signed_request(payload, signature=None):
    raw_body = json.dumps(payload, separators=(",", ":")).encode()
    timestamp = now()
    signature = signature or create_signature(
        SECRET, timestamp, "POST", CUSTOMER_PATH, raw_body
    )
    headers = {
        "content-type": "application/json",
        "x-api-key": API_KEY,
        "x-tenant-id": TENANT,
        "x-event-id": payload["event_id"],
        "x-idempotency-key": payload["idempotency_key"],
        "x-timestamp": timestamp,
        "x-signature": signature,
    }
    delivered = False

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.disconnect"}
        delivered = True
        return {"type": "http.request", "body": raw_body, "more_body": False}

    return Request({
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "https",
        "path": CUSTOMER_PATH,
        "raw_path": CUSTOMER_PATH.encode(),
        "query_string": b"",
        "headers": [(key.encode(), value.encode()) for key, value in headers.items()],
        "client": ("127.0.0.1", 50000),
        "server": ("testserver", 443),
    }, receive)


def test_required_integration_routes_are_published():
    paths = app.openapi()["paths"]
    assert "/api/integrations/medusa/v1/orders" in paths
    assert "/api/integrations/medusa/v1/orders/{external_order_id}" in paths
    assert "/api/integrations/medusa/v1/payments/captured" in paths
    assert "/api/integrations/medusa/v1/customers" in paths
    assert REQUIRED_SCHEMA_REVISION == "20260718_0005"


def test_customer_create_maps_canonical_customer_and_replays(database):
    db, _, _ = database
    service = CartunezCustomerService()
    payload = customer_payload()
    first = asyncio.run(service.process_create(signed_request(payload), db))
    replay = asyncio.run(service.process_create(signed_request(payload), db))

    assert first.status_code == 201
    assert first.body["data"]["created"] is True
    assert first.body["data"]["customer"]["apexbooks_customer_id"].startswith("ab_customer_")
    assert replay.status_code == 200
    assert replay.headers["Idempotency-Replayed"] == "true"
    assert db.query(Contact).one().email == "amit.sharma@cartunez.in"
    assert db.query(Contact).one().custom_fields["credit_terms_days"] == 15


def test_customer_invalid_signature_is_contract_error(database):
    db, _, _ = database
    result = asyncio.run(CartunezCustomerService().process_create(
        signed_request(customer_payload(), "sha256=" + "0" * 64), db
    ))
    assert result.status_code == 403
    assert result.body["success"] is False
    assert result.body["error"]["code"] == "SIGNATURE_INVALID"
    assert db.query(Contact).count() == 0


def test_outbound_master_delivery_signs_logs_and_completes(database, monkeypatch):
    db, tenant, _ = database
    payload = {
        "event_id": "evt_01ARZ3NDEKTSV4RRFFQ69G5FBD",
        "event_name": "product.changed",
        "event_version": "v1",
        "tenant_id": TENANT,
        "occurred_at": now(),
        "source_system": "APEXBOOKS",
        "source_id": "ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY",
        "idempotency_key": f"{TENANT}:product.changed:ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY:v1",
        "product": {"contract_payload": "already validated by producer"},
    }
    event = CartunezOutboundDispatcher.enqueue(db, tenant.id, payload)
    db.commit()
    db.refresh(event)

    monkeypatch.setattr(settings, "CARTUNEZ_OUTBOUND_ENABLED", True)
    monkeypatch.setattr(settings, "CARTUNEZ_MEDUSA_BASE_URL", "https://medusa.example")
    monkeypatch.setattr(settings, "CARTUNEZ_MEDUSA_API_KEY", MEDUSA_API_KEY)

    class Response:
        status_code = 200
        content = b'{"success":true,"data":{},"meta":{}}'

        @staticmethod
        def json():
            return {"success": True, "data": {}, "meta": {}}

    def fake_put(url, data, headers, timeout):
        assert url == (
            "https://medusa.example/api/integrations/apexbooks/v1/products/"
            "ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY"
        )
        expected = create_signature(
            SECRET,
            headers["X-Timestamp"],
            "PUT",
            "/api/integrations/apexbooks/v1/products/ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY",
            data,
        )
        assert headers["X-Signature"] == expected
        assert headers["X-Api-Key"] == MEDUSA_API_KEY
        return Response()

    monkeypatch.setattr("src.integrations.cartunez.outbound.requests.put", fake_put)
    result = CartunezOutboundDispatcher().deliver(db, event.id)

    assert result.delivered is True
    assert db.get(WebhookEvent, event.id).status == "DELIVERED"
    log = db.query(IntegrationEventLog).filter(IntegrationEventLog.direction == "OUTBOUND").one()
    assert log.status == "COMPLETED" and log.response_status == 200


def test_outbound_transient_failure_remains_pending_for_retry(database, monkeypatch):
    db, tenant, _ = database
    payload = {
        "event_id": "evt_01ARZ3NDEKTSV4RRFFQ69G5FBE",
        "event_name": "price.updated",
        "event_version": "v1",
        "tenant_id": TENANT,
        "occurred_at": now(),
        "source_system": "APEXBOOKS",
        "source_id": "ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY",
        "idempotency_key": f"{TENANT}:price.updated:ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY:v1",
    }
    event = CartunezOutboundDispatcher.enqueue(db, tenant.id, payload, max_retries=3)
    db.commit()
    monkeypatch.setattr(settings, "CARTUNEZ_OUTBOUND_ENABLED", True)
    monkeypatch.setattr(settings, "CARTUNEZ_MEDUSA_BASE_URL", "https://medusa.example")
    monkeypatch.setattr(settings, "CARTUNEZ_MEDUSA_API_KEY", MEDUSA_API_KEY)

    def unavailable(*args, **kwargs):
        import requests
        raise requests.Timeout("timed out")

    monkeypatch.setattr("src.integrations.cartunez.outbound.requests.put", unavailable)
    result = CartunezOutboundDispatcher().deliver(db, event.id)

    queued = db.get(WebhookEvent, event.id)
    assert result.retryable is True
    assert queued.status == "PENDING" and queued.retry_count == 1
    assert db.query(IntegrationEventLog).filter(
        IntegrationEventLog.direction == "OUTBOUND",
        IntegrationEventLog.status == "FAILED",
    ).count() == 1
