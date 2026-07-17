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
from src.infrastructure.database.models import Tenant
from src.integrations.cartunez.master_models import (
    MasterSyncAudit,
    SyncedCustomer,
    SyncedInventoryLevel,
    SyncedPrice,
    SyncedProduct,
)
from src.integrations.cartunez.master_service import CartunezMasterDataService
from src.integrations.core.models import IntegrationConnection, IntegrationEntityMap
from src.integrations.core.signatures import create_signature


API_KEY = "ctz_live_7f91f651f6f64564a588a347a7f56c8e"
SECRET = "cartunez-test-hmac-secret-at-least-32-bytes"
TENANT = "tenant_cartunez_in"
PRODUCT = "ab_product_01ARZ3NDEKTSV4RRFFQ69G5FAY"
VARIANT = "ab_variant_01ARZ3NDEKTSV4RRFFQ69G5FAZ"
WAREHOUSE = "ab_warehouse_01ARZ3NDEKTSV4RRFFQ69G5FBG"
CUSTOMER = "ab_customer_01ARZ3NDEKTSV4RRFFQ69G5FB2"


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def envelope(event_id, event_name, source_id):
    return {
        "event_id": event_id,
        "event_name": event_name,
        "event_version": "v1",
        "tenant_id": TENANT,
        "occurred_at": utc_now(),
        "source_system": "APEXBOOKS",
        "source_id": source_id,
        "idempotency_key": f"{TENANT}:{event_name}:{source_id}:v1",
    }


def product_payload(event_id="evt_01ARZ3NDEKTSV4RRFFQ69G5FBD", source_id=PRODUCT):
    value = envelope(event_id, "product.changed", source_id)
    value["product"] = {
        "apexbooks_product_id": PRODUCT,
        "title": "H7 LED Headlamp Pair",
        "description": "Road-legal headlamp pair.",
        "hsn_sac": "851220",
        "gst_rate_bps": 1800,
        "active": True,
        "categories": ["Lighting", "Headlamps"],
        "images": ["https://cdn.cartunez.in/front.webp"],
        "variants": [{
            "apexbooks_variant_id": VARIANT,
            "sku": "LED-H7",
            "title": "H7 Pair",
            "product_type": "GOODS",
            "active": True,
        }],
        "updated_at": utc_now(),
    }
    return value


def price_payload(event_id="evt_01ARZ3NDEKTSV4RRFFQ69G5FBE", source_id=PRODUCT):
    value = envelope(event_id, "price.updated", source_id)
    value["price_update"] = {
        "apexbooks_product_id": PRODUCT,
        "replace_all": True,
        "prices": [{
            "apexbooks_variant_id": VARIANT,
            "currency_code": "INR",
            "amount_minor": 118000,
            "tax_inclusive": True,
            "price_list_id": "RETAIL-IN-2026",
            "valid_from": utc_now(),
            "valid_to": None,
        }],
        "updated_at": utc_now(),
    }
    return value


def inventory_payload(event_id="evt_01ARZ3NDEKTSV4RRFFQ69G5FBF", source_id=PRODUCT):
    value = envelope(event_id, "inventory.updated", source_id)
    value["inventory_update"] = {
        "apexbooks_product_id": PRODUCT,
        "replace_all": True,
        "levels": [{
            "apexbooks_variant_id": VARIANT,
            "warehouse_id": WAREHOUSE,
            "available_quantity": 24,
            "reserved_quantity": 2,
            "updated_at": utc_now(),
        }],
        "updated_at": utc_now(),
    }
    return value


def customer_payload(event_id="evt_01ARZ3NDEKTSV4RRFFQ69G5FBH", source_id=CUSTOMER):
    value = envelope(event_id, "customer.updated", source_id)
    address = {
        "name": "Amit Sharma", "company": "Amit Auto Works", "phone": "+919999999999",
        "address_1": "24 Linking Road", "address_2": "Bandra West", "city": "Mumbai",
        "state": "Maharashtra", "state_code": "27", "postal_code": "400050", "country_code": "IN",
    }
    value["customer"] = {
        "apexbooks_customer_id": CUSTOMER,
        "medusa_customer_id": "cus_01ARZ3NDEKTSV4RRFFQ69G5FAX",
        "accounting_email": "accounts@amitautoworks.in",
        "first_name": "Amit", "last_name": "Sharma", "phone": "+919999999999",
        "gst": {"gstin": "27ABCDE1234F1Z5", "gst_type": "REGULAR", "state_code": "27"},
        "billing_address": address, "shipping_address": copy.deepcopy(address),
        "credit_terms_days": 15, "active": True, "updated_at": utc_now(),
    }
    return value


def make_request(payload, path, signature=None, tenant=TENANT):
    body = json.dumps(payload, separators=(",", ":")).encode()
    timestamp = utc_now()
    signature = signature or create_signature(SECRET, timestamp, "PUT", path, body)
    headers = {
        "content-type": "application/json", "x-api-key": API_KEY, "x-tenant-id": tenant,
        "x-event-id": payload["event_id"], "x-idempotency-key": payload["idempotency_key"],
        "x-timestamp": timestamp, "x-signature": signature,
    }
    delivered = False

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.disconnect"}
        delivered = True
        return {"type": "http.request", "body": body, "more_body": False}

    return Request({
        "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "PUT",
        "scheme": "https", "path": path, "raw_path": path.encode(), "query_string": b"",
        "headers": [(key.encode(), val.encode()) for key, val in headers.items()],
        "client": ("127.0.0.1", 50000), "server": ("testserver", 443),
    }, receive)


def seed_connection(db):
    tenant = Tenant(id=uuid.uuid4(), legal_name="Master Test", trade_name="Master", financial_year_start=datetime.now().date())
    db.add(tenant)
    connection = IntegrationConnection(
        tenant_id=tenant.id, integration_name="cartunez", external_tenant_id=TENANT,
        api_key_prefix="pending", api_key_hash="pending", hmac_secret_encrypted="pending", status="ENABLED",
    )
    connection.set_api_key(API_KEY)
    connection.set_hmac_secret(SECRET)
    db.add(connection)
    db.commit()


@pytest.fixture
def database(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'master.db'}", connect_args={"check_same_thread": False, "timeout": 10})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = factory()
    seed_connection(db)
    yield db, factory
    db.close()
    engine.dispose()


def execute(service, db, kind, payload, entity_id, **request_options):
    path = f"/api/integrations/apexbooks/v1/{kind}/{entity_id}"
    request = make_request(payload, path, **request_options)
    method = {"products": service.process_product, "prices": service.process_prices,
              "inventory": service.process_inventory, "customers": service.process_customer}[kind]
    return asyncio.run(method(request, db, entity_id))


def seed_product(service, db):
    result = execute(service, db, "products", product_payload(), PRODUCT)
    assert result.status_code == 201


def test_product_sync(database):
    db, _ = database
    result = execute(CartunezMasterDataService(), db, "products", product_payload(), PRODUCT)
    assert result.status_code == 201 and result.body["success"] is True
    assert db.query(SyncedProduct).one().title == "H7 LED Headlamp Pair"
    assert db.query(IntegrationEntityMap).count() == 2
    assert db.query(MasterSyncAudit).one().old_values is None


def test_product_update_without_duplicate_mapping(database):
    db, _ = database
    service = CartunezMasterDataService()
    seed_product(service, db)
    updated = product_payload("evt_01ARZ3NDEKTSV4RRFFQ69G5FC4", "ab_change_01ARZ3NDEKTSV4RRFFQ69G5FC5")
    updated["product"]["title"] = "Updated H7 Headlamp"
    result = execute(service, db, "products", updated, PRODUCT)
    assert result.status_code == 200
    assert db.query(SyncedProduct).one().title == "Updated H7 Headlamp"
    assert db.query(IntegrationEntityMap).count() == 2
    assert db.query(MasterSyncAudit).order_by(MasterSyncAudit.created_at.desc()).first().old_values is not None


def test_duplicate_product_event_replays(database):
    db, _ = database
    service = CartunezMasterDataService()
    payload = product_payload()
    first = execute(service, db, "products", payload, PRODUCT)
    second = execute(service, db, "products", payload, PRODUCT)
    assert first.status_code == 201 and second.status_code == 200
    assert second.headers["Idempotency-Replayed"] == "true"
    assert db.query(SyncedProduct).count() == 1 and db.query(MasterSyncAudit).count() == 1


def test_price_update_replaces_active_prices(database):
    db, _ = database
    service = CartunezMasterDataService(); seed_product(service, db)
    first = execute(service, db, "prices", price_payload(), PRODUCT)
    updated = price_payload("evt_01ARZ3NDEKTSV4RRFFQ69G5FC6", "ab_change_01ARZ3NDEKTSV4RRFFQ69G5FC7")
    updated["price_update"]["prices"][0]["amount_minor"] = 125000
    second = execute(service, db, "prices", updated, PRODUCT)
    assert first.status_code == 201 and second.status_code == 200
    assert db.query(SyncedPrice).one().amount_minor == 125000


def test_inventory_update_is_atomic_replacement(database):
    db, _ = database
    service = CartunezMasterDataService(); seed_product(service, db)
    result = execute(service, db, "inventory", inventory_payload(), PRODUCT)
    row = db.query(SyncedInventoryLevel).one()
    assert result.status_code == 201 and row.available_quantity == 24 and row.reserved_quantity == 2


def test_inventory_replay(database):
    db, _ = database
    service = CartunezMasterDataService(); seed_product(service, db)
    payload = inventory_payload()
    execute(service, db, "inventory", payload, PRODUCT)
    replay = execute(service, db, "inventory", payload, PRODUCT)
    assert replay.status_code == 200 and replay.headers["Idempotency-Replayed"] == "true"
    assert db.query(SyncedInventoryLevel).count() == 1


def test_customer_update_only_business_projection(database):
    db, _ = database
    result = execute(CartunezMasterDataService(), db, "customers", customer_payload(), CUSTOMER)
    customer = db.query(SyncedCustomer).one()
    assert result.status_code == 201 and customer.credit_terms_days == 15
    assert "password" not in SyncedCustomer.__table__.columns and "credentials" not in SyncedCustomer.__table__.columns


def test_invalid_schema(database):
    db, _ = database
    payload = product_payload(); payload["product"]["metadata"] = {"forbidden": True}
    result = execute(CartunezMasterDataService(), db, "products", payload, PRODUCT)
    assert result.status_code == 400 and result.body["error"]["code"] == "VALIDATION_ERROR"
    assert db.query(SyncedProduct).count() == 0


def test_invalid_signature(database):
    db, _ = database
    result = execute(CartunezMasterDataService(), db, "products", product_payload(), PRODUCT, signature="sha256=" + "0" * 64)
    assert result.status_code == 403 and result.body["error"]["code"] == "SIGNATURE_INVALID"


def test_invalid_tenant(database):
    db, _ = database
    payload = product_payload(); payload["tenant_id"] = "tenant_other"
    payload["idempotency_key"] = f"tenant_other:product.changed:{PRODUCT}:v1"
    result = execute(CartunezMasterDataService(), db, "products", payload, PRODUCT, tenant="tenant_other")
    assert result.status_code == 403 and result.body["error"]["code"] == "TENANT_NOT_RESOLVED"


def test_rollback_preserves_previous_price_set(database, monkeypatch):
    db, _ = database
    service = CartunezMasterDataService(); seed_product(service, db)
    execute(service, db, "prices", price_payload(), PRODUCT)
    updated = price_payload("evt_01ARZ3NDEKTSV4RRFFQ69G5FC8", "ab_change_01ARZ3NDEKTSV4RRFFQ69G5FC9")
    updated["price_update"]["prices"][0]["amount_minor"] = 999999
    monkeypatch.setattr(service, "_audit", lambda *args: (_ for _ in ()).throw(RuntimeError("fail")))
    result = execute(service, db, "prices", updated, PRODUCT)
    assert result.status_code == 500
    assert db.query(SyncedPrice).one().amount_minor == 118000


def test_concurrent_duplicate_requests_execute_once(database):
    db, factory = database
    service = CartunezMasterDataService(); seed_product(service, db)
    payload = inventory_payload()
    barrier = threading.Barrier(2)

    def run():
        session = factory(); barrier.wait()
        try:
            return execute(CartunezMasterDataService(), session, "inventory", payload, PRODUCT)
        finally:
            session.close()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: run(), range(2)))
    assert sorted(item.status_code for item in results) == [200, 201]
    assert db.query(SyncedInventoryLevel).count() == 1


def test_duplicate_idempotency_key_with_new_event_conflicts(database):
    db, _ = database
    service = CartunezMasterDataService(); payload = product_payload()
    execute(service, db, "products", payload, PRODUCT)
    duplicate_key = copy.deepcopy(payload)
    duplicate_key["event_id"] = "evt_01ARZ3NDEKTSV4RRFFQ69G5FDA"
    result = execute(service, db, "products", duplicate_key, PRODUCT)
    assert result.status_code == 409 and result.body["error"]["code"] == "IDEMPOTENCY_CONFLICT"
