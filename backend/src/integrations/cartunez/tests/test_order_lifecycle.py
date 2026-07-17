from __future__ import annotations

import asyncio
import copy
import json
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

from src.core.database import Base
from src.infrastructure.database.models import SalesOrder, Tenant
from src.integrations.cartunez.master_models import (
    SyncedCustomer, SyncedInventoryLevel, SyncedPrice, SyncedProduct, SyncedProductVariant,
)
from src.integrations.cartunez.order_models import (
    IntegrationInventoryMovement, IntegrationOrderAudit, IntegrationOrderState,
)
from src.integrations.cartunez.order_service import CartunezOrderService
from src.integrations.core.models import IntegrationConnection, IntegrationEntityMap
from src.integrations.core.signatures import create_signature


API_KEY = "ctz_live_7f91f651f6f64564a588a347a7f56c8e"
SECRET = "cartunez-test-hmac-secret-at-least-32-bytes"
TENANT = "tenant_cartunez_in"
ORDER = "order_01ARZ3NDEKTSV4RRFFQ69G5FAV"
CUSTOMER = "ab_customer_01ARZ3NDEKTSV4RRFFQ69G5FB2"
MEDUSA_CUSTOMER = "cus_01ARZ3NDEKTSV4RRFFQ69G5FAX"
PRODUCT = "ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY"
VARIANT = "ab_variant_01ARZ3NDEKTSV4RRFFQ69G5FAZ"
MEDUSA_PRODUCT = "prod_01ARZ3NDEKTSV4RRFFQ69G5FAY"
MEDUSA_VARIANT = "variant_01ARZ3NDEKTSV4RRFFQ69G5FAZ"
WAREHOUSE = "ab_warehouse_01ARZ3NDEKTSV4RRFFQ69G5FBG"


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def address(street="24 Linking Road"):
    return {
        "name": "Amit Sharma", "company": None, "phone": "+919999999999",
        "address_1": street, "address_2": "Bandra West", "city": "Mumbai",
        "state": "Maharashtra", "state_code": "27", "postal_code": "400050", "country_code": "IN",
    }


def envelope(event_id, event_name):
    return {
        "event_id": event_id, "event_name": event_name, "event_version": "v1",
        "tenant_id": TENANT, "occurred_at": now(), "source_system": "MEDUSA", "source_id": ORDER,
        "idempotency_key": f"{TENANT}:{event_name}:{ORDER}:v1",
    }


def snapshot(revision=1):
    billing = address()
    return {
        "medusa_order_id": ORDER, "display_id": 1001, "order_revision": revision,
        "currency_code": "INR", "seller_state_code": "27", "place_of_supply_state_code": "27",
        "customer": {
            "medusa_customer_id": MEDUSA_CUSTOMER, "apexbooks_customer_id": CUSTOMER,
            "accounting_email": "accounts@amitautoworks.in", "first_name": "Amit", "last_name": "Sharma",
            "phone": "+919999999999", "gst": {"gstin": None, "gst_type": "CONSUMER", "state_code": "27"},
            "billing_address": billing, "shipping_address": copy.deepcopy(billing), "credit_terms_days": 0,
        },
        "billing_address": billing, "shipping_address": copy.deepcopy(billing),
        "lines": [{
            "medusa_line_id": "item_01ARZ3NDEKTSV4RRFFQ69G5FB0",
            "medusa_product_id": MEDUSA_PRODUCT, "medusa_variant_id": MEDUSA_VARIANT,
            "apexbooks_product_id": PRODUCT, "apexbooks_variant_id": VARIANT,
            "sku": "LED-H7", "title": "H7 LED Headlamp Pair", "product_type": "GOODS", "quantity": 1,
            "unit_price": {"currency_code": "INR", "amount_minor": 118000}, "tax_inclusive": True,
            "discount": {"currency_code": "INR", "amount_minor": 0},
            "gst": {
                "hsn_sac": "851220", "gst_rate_bps": 1800, "taxable_value_minor": 100000,
                "discount_minor": 0, "cgst_rate_bps": 900, "cgst_amount_minor": 9000,
                "sgst_rate_bps": 900, "sgst_amount_minor": 9000, "igst_rate_bps": 0,
                "igst_amount_minor": 0, "cess_rate_bps": 0, "cess_amount_minor": 0,
                "tax_amount_minor": 18000,
            },
            "line_total": {"currency_code": "INR", "amount_minor": 118000},
        }],
        "shipping": {
            "title": "Shipping", "unit_price": {"currency_code": "INR", "amount_minor": 0},
            "tax_inclusive": False, "discount": {"currency_code": "INR", "amount_minor": 0},
            "gst": {
                "hsn_sac": "996812", "gst_rate_bps": 1800, "taxable_value_minor": 0,
                "discount_minor": 0, "cgst_rate_bps": 900, "cgst_amount_minor": 0,
                "sgst_rate_bps": 900, "sgst_amount_minor": 0, "igst_rate_bps": 0,
                "igst_amount_minor": 0, "cess_rate_bps": 0, "cess_amount_minor": 0,
                "tax_amount_minor": 0,
            },
            "line_total": {"currency_code": "INR", "amount_minor": 0},
        },
        "totals": {
            "items_gross": {"currency_code": "INR", "amount_minor": 118000},
            "discount_total": {"currency_code": "INR", "amount_minor": 0},
            "taxable_total": {"currency_code": "INR", "amount_minor": 100000},
            "tax_total": {"currency_code": "INR", "amount_minor": 18000},
            "shipping_total": {"currency_code": "INR", "amount_minor": 0},
            "grand_total": {"currency_code": "INR", "amount_minor": 118000},
        },
        "customer_reference": "WEB-1001", "notes": "Deliver during business hours.",
        "placed_at": "2026-07-17T10:00:00Z",
    }


def created_payload():
    value = envelope("evt_01ARZ3NDEKTSV4RRFFQ69G5FAW", "order.created")
    value["order"] = snapshot(1)
    return value


def updated_payload():
    value = envelope("evt_01ARZ3NDEKTSV4RRFFQ69G5FB1", "order.updated")
    value["expected_order_revision"] = 1
    value["order"] = snapshot(2)
    value["order"]["shipping_address"] = address("25 Linking Road")
    value["order"]["notes"] = "Use the corrected delivery address."
    return value


def cancelled_payload(revision=1):
    value = envelope("evt_01ARZ3NDEKTSV4RRFFQ69G5FB3", "order.cancelled")
    value["cancellation"] = {
        "medusa_order_id": ORDER, "expected_order_revision": revision,
        "reason_code": "CUSTOMER_REQUEST", "reason": "Buyer requested cancellation.", "cancelled_at": now(),
    }
    return value


def request_for(payload, method, path):
    raw = json.dumps(payload, separators=(",", ":")).encode()
    timestamp = now()
    headers = {
        "content-type": "application/json", "x-api-key": API_KEY, "x-tenant-id": TENANT,
        "x-event-id": payload["event_id"], "x-idempotency-key": payload["idempotency_key"],
        "x-timestamp": timestamp, "x-signature": create_signature(SECRET, timestamp, method, path, raw),
    }
    delivered = False

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.disconnect"}
        delivered = True
        return {"type": "http.request", "body": raw, "more_body": False}

    return Request({
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": method,
        "scheme": "https", "path": path, "raw_path": path.encode(), "query_string": b"",
        "headers": [(key.encode(), val.encode()) for key, val in headers.items()],
        "client": ("127.0.0.1", 50000), "server": ("testserver", 443),
    }, receive)


def execute(service, db, operation, payload):
    if operation == "create":
        path, method = "/api/integrations/medusa/v1/orders", "POST"
        return asyncio.run(service.process_create(request_for(payload, method, path), db))
    if operation == "update":
        path, method = f"/api/integrations/medusa/v1/orders/{ORDER}", "PATCH"
        return asyncio.run(service.process_update(request_for(payload, method, path), db, ORDER))
    path, method = f"/api/integrations/medusa/v1/orders/{ORDER}/cancel", "POST"
    return asyncio.run(service.process_cancel(request_for(payload, method, path), db, ORDER))


def seed(db):
    tenant = Tenant(id=uuid.uuid4(), legal_name="Order Test", trade_name="Order Test", financial_year_start=datetime.now().date())
    db.add(tenant)
    connection = IntegrationConnection(
        tenant_id=tenant.id, integration_name="cartunez", external_tenant_id=TENANT,
        api_key_prefix="pending", api_key_hash="pending", hmac_secret_encrypted="pending", status="ENABLED",
    )
    connection.set_api_key(API_KEY); connection.set_hmac_secret(SECRET); db.add(connection)
    customer_id, product_id, variant_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    db.add(SyncedCustomer(
        id=customer_id, tenant_id=tenant.id, apexbooks_customer_id=CUSTOMER, medusa_customer_id=MEDUSA_CUSTOMER,
        first_name="Amit", last_name="Sharma", phone="+919999999999", accounting_email="accounts@amitautoworks.in",
        gstin=None, gst_type="CONSUMER", billing_address=address(), shipping_address=address(), state_code="27",
        credit_terms_days=0, active=True, source_updated_at=datetime.now(timezone.utc),
    ))
    db.add(SyncedProduct(
        id=product_id, tenant_id=tenant.id, apexbooks_product_id=PRODUCT, medusa_product_id=MEDUSA_PRODUCT,
        title="H7 LED Headlamp Pair", description="Headlamp", categories=["Lighting"], images=[], active=True,
        hsn_sac="851220", gst_rate_bps=1800, source_updated_at=datetime.now(timezone.utc),
    ))
    db.add(SyncedProductVariant(
        id=variant_id, tenant_id=tenant.id, product_id=product_id, apexbooks_variant_id=VARIANT,
        medusa_variant_id=MEDUSA_VARIANT, sku="LED-H7", title="H7 Pair", product_type="GOODS", active=True,
    ))
    for entity_type, external_id, internal_id in (
        ("customer", CUSTOMER, customer_id), ("product", PRODUCT, product_id), ("variant", VARIANT, variant_id),
    ):
        db.add(IntegrationEntityMap(
            tenant_id=tenant.id, integration_name="cartunez", entity_type=entity_type,
            external_id=external_id, internal_id=internal_id, sync_status="SYNCED",
        ))
    db.add(SyncedPrice(
        tenant_id=tenant.id, product_id=product_id, variant_id=variant_id, amount_minor=118000,
        currency_code="INR", tax_inclusive=True, price_list_id="RETAIL", valid_from=datetime(2026, 1, 1, tzinfo=timezone.utc),
        valid_to=None, source_updated_at=datetime.now(timezone.utc),
    ))
    db.add(SyncedInventoryLevel(
        tenant_id=tenant.id, product_id=product_id, variant_id=variant_id, warehouse_id=WAREHOUSE,
        available_quantity=24, reserved_quantity=2, source_updated_at=datetime.now(timezone.utc),
    ))
    db.commit()


@pytest.fixture
def database(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'orders.db'}", connect_args={"check_same_thread": False, "timeout": 10})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = factory(); seed(db)
    yield db, factory
    db.close(); engine.dispose()


def create_order(service, db):
    result = execute(service, db, "create", created_payload())
    assert result.status_code == 201
    return result


def test_order_create(database):
    db, _ = database
    result = create_order(CartunezOrderService(), db)
    assert result.body["data"]["order_status"] == "DRAFT" and result.body["data"]["apexbooks_invoice_id"] is None
    assert db.query(SalesOrder).one().status == "DRAFT"
    assert db.query(SyncedInventoryLevel).one().reserved_quantity == 3
    assert db.query(IntegrationOrderAudit).one().result == "CREATED"


def test_duplicate_order(database):
    db, _ = database; service = CartunezOrderService(); payload = created_payload()
    first = execute(service, db, "create", payload); second = execute(service, db, "create", payload)
    assert first.status_code == 201 and second.status_code == 200
    assert second.headers["Idempotency-Replayed"] == "true" and db.query(SalesOrder).count() == 1


def test_order_update(database):
    db, _ = database; service = CartunezOrderService(); create_order(service, db)
    result = execute(service, db, "update", updated_payload())
    assert result.status_code == 200 and result.body["data"]["order_revision"] == 2
    assert db.query(IntegrationOrderState).one().commercial_snapshot["shipping_address"]["address_1"] == "25 Linking Road"
    assert db.query(SyncedInventoryLevel).one().reserved_quantity == 3


def test_immutable_update_rejection(database):
    db, _ = database; service = CartunezOrderService(); create_order(service, db)
    state = db.query(IntegrationOrderState).one(); state.status = "PARTIALLY_PAID"; state.captured_amount_minor = 100; db.commit()
    result = execute(service, db, "update", updated_payload())
    assert result.status_code == 409 and result.body["error"]["code"] == "ORDER_IMMUTABLE"


def test_cancel_unpaid(database):
    db, _ = database; service = CartunezOrderService(); create_order(service, db)
    result = execute(service, db, "cancel", cancelled_payload())
    assert result.status_code == 200 and result.body["data"]["order_status"] == "CANCELLED"
    assert db.query(SalesOrder).one().status == "CANCELLED"
    assert db.query(SyncedInventoryLevel).one().reserved_quantity == 2


def test_cancel_invoiced_requires_refund_without_credit_note(database):
    db, _ = database; service = CartunezOrderService(); create_order(service, db)
    state = db.query(IntegrationOrderState).one(); state.apexbooks_invoice_id = "ab_invoice_01ARZ3NDEKTSV4RRFFQ69G5FZZ"; db.commit()
    result = execute(service, db, "cancel", cancelled_payload())
    assert result.status_code == 409 and result.body["error"]["code"] == "REFUND_REQUIRED"
    assert db.query(SalesOrder).one().status == "DRAFT" and db.query(SyncedInventoryLevel).one().reserved_quantity == 3


def test_invalid_customer(database):
    db, _ = database; payload = created_payload()
    payload["order"]["customer"]["medusa_customer_id"] = "cus_01ARZ3NDEKTSV4RRFFQ69G5FQQ"
    payload["order"]["customer"]["apexbooks_customer_id"] = None
    result = execute(CartunezOrderService(), db, "create", payload)
    assert result.status_code == 404 and result.body["error"]["code"] == "RESOURCE_NOT_FOUND"


def test_invalid_product(database):
    db, _ = database; payload = created_payload()
    payload["order"]["lines"][0]["apexbooks_product_id"] = "ab_product_01ARZ3NDEKTSV4RRFFQ69G5FQQ"
    result = execute(CartunezOrderService(), db, "create", payload)
    assert result.status_code == 404 and result.body["error"]["code"] == "RESOURCE_NOT_FOUND"


def test_gst_validation(database):
    db, _ = database; payload = created_payload(); payload["order"]["lines"][0]["gst"]["cgst_amount_minor"] = 8999
    result = execute(CartunezOrderService(), db, "create", payload)
    assert result.status_code == 422 and result.body["error"]["code"] == "GST_MISMATCH"


def test_replay_event_id_with_changed_body(database):
    db, _ = database; service = CartunezOrderService(); payload = created_payload()
    execute(service, db, "create", payload)
    changed = copy.deepcopy(payload); changed["order"]["notes"] = "Changed replay body"
    result = execute(service, db, "create", changed)
    assert result.status_code == 409 and result.body["error"]["code"] == "REPLAY_DETECTED"


def test_rollback(database, monkeypatch):
    db, _ = database; service = CartunezOrderService()
    monkeypatch.setattr(service, "_audit", lambda *args: (_ for _ in ()).throw(RuntimeError("audit failed")))
    result = execute(service, db, "create", created_payload())
    assert result.status_code == 500
    assert db.query(SalesOrder).count() == 0 and db.query(IntegrationOrderState).count() == 0
    assert db.query(SyncedInventoryLevel).one().reserved_quantity == 2


def test_concurrency(database):
    db, factory = database; payload = created_payload(); barrier = threading.Barrier(2)
    def run():
        session = factory(); barrier.wait()
        try:
            return execute(CartunezOrderService(), session, "create", payload)
        finally:
            session.close()
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: run(), range(2)))
    assert sorted(result.status_code for result in results) == [200, 201]
    assert db.query(SalesOrder).count() == 1 and db.query(SyncedInventoryLevel).one().reserved_quantity == 3
