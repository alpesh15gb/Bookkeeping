from __future__ import annotations

import asyncio
import json
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.requests import Request

from src.core.database import Base
from src.infrastructure.database.models import Tenant
from src.integrations.cartunez.service import CartunezIntegrationService
from src.integrations.core.idempotency import HandlerResult
from src.integrations.core.models import (
    IntegrationConnection,
    IntegrationEntityMap,
    IntegrationEventLog,
    IntegrationReplayCache,
)
from src.integrations.core.signatures import create_signature


API_KEY = "ctz_live_7f91f651f6f64564a588a347a7f56c8e"
HMAC_SECRET = "cartunez-test-hmac-secret-at-least-32-bytes"
EXTERNAL_TENANT = "tenant_cartunez_in"
PATH = "/api/integrations/medusa/v1/foundation-test"


def create_connection(db, tenant) -> IntegrationConnection:
    connection = IntegrationConnection(
        tenant_id=tenant.id,
        integration_name="cartunez",
        external_tenant_id=EXTERNAL_TENANT,
        api_key_prefix="pending",
        api_key_hash="pending",
        hmac_secret_encrypted="pending",
        status="ENABLED",
    )
    connection.set_api_key(API_KEY)
    connection.set_hmac_secret(HMAC_SECRET)
    db.add(connection)
    db.commit()
    db.refresh(connection)
    return connection


def event_payload(
    event_id: str = "evt_01ARZ3NDEKTSV4RRFFQ69G5FAW",
    source_id: str = "foundation_01ARZ3NDEKTSV4RRFFQ69G5FAV",
    idempotency_key: str | None = None,
) -> dict:
    event_name = "foundation.test"
    return {
        "event_id": event_id,
        "event_name": event_name,
        "event_version": "v1",
        "tenant_id": EXTERNAL_TENANT,
        "occurred_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source_system": "MEDUSA",
        "source_id": source_id,
        "idempotency_key": idempotency_key
        or f"{EXTERNAL_TENANT}:{event_name}:{source_id}:v1",
        "foundation": {"probe": True},
    }


def make_request(
    payload: dict,
    *,
    api_key: str = API_KEY,
    secret: str = HMAC_SECRET,
    timestamp: str | None = None,
    tenant_id: str = EXTERNAL_TENANT,
    signature: str | None = None,
) -> Request:
    raw_body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    timestamp = timestamp or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    signature = signature or create_signature(secret, timestamp, "POST", PATH, raw_body)
    headers = {
        "content-type": "application/json",
        "x-api-key": api_key,
        "x-tenant-id": tenant_id,
        "x-event-id": payload["event_id"],
        "x-idempotency-key": payload["idempotency_key"],
        "x-timestamp": timestamp,
        "x-signature": signature,
    }
    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "https",
        "path": PATH,
        "raw_path": PATH.encode("ascii"),
        "query_string": b"",
        "headers": [(key.encode("ascii"), value.encode("utf-8")) for key, value in headers.items()],
        "client": ("127.0.0.1", 50000),
        "server": ("testserver", 443),
    }
    delivered = False

    async def receive():
        nonlocal delivered
        if delivered:
            return {"type": "http.disconnect"}
        delivered = True
        return {"type": "http.request", "body": raw_body, "more_body": False}

    return Request(scope, receive)


def run_request(service, db, request, handler):
    return asyncio.run(service.process_foundation_request(request, db, handler))


@pytest.fixture
def db_session(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'integration-foundation.db'}",
        connect_args={"check_same_thread": False, "timeout": 10},
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = session_factory()
    try:
        yield db
    finally:
        db.close()
        engine.dispose()


@pytest.fixture
def tenant(db_session):
    tenant = Tenant(
        id=uuid.uuid4(),
        legal_name="Foundation Test Tenant",
        trade_name="Foundation Test",
        financial_year_start=datetime.now().date(),
    )
    db_session.add(tenant)
    db_session.commit()
    db_session.refresh(tenant)
    return tenant


@pytest.fixture
def integration_connection(db_session, tenant):
    return create_connection(db_session, tenant)


@pytest.fixture
def service():
    return CartunezIntegrationService()


def accepted_handler(db, authenticated):
    return HandlerResult(
        status_code=202,
        body={"accepted": True, "event_id": authenticated.envelope.event_id},
    )


def test_valid_request_is_authenticated_logged_and_cached(
    db_session,
    integration_connection,
    service,
):
    result = run_request(service, db_session, make_request(event_payload()), accepted_handler)

    assert result.status_code == 202
    assert result.body["accepted"] is True
    replay = db_session.query(IntegrationReplayCache).one()
    assert replay.status == "COMPLETED"
    assert replay.request_hash
    event_log = db_session.query(IntegrationEventLog).one()
    assert event_log.status == "COMPLETED"
    assert event_log.tenant_id == integration_connection.tenant_id
    assert event_log.processing_time_ms is not None


def test_invalid_api_key_is_rejected_and_logged(db_session, integration_connection, service):
    result = run_request(
        service,
        db_session,
        make_request(event_payload(), api_key="invalid-api-key-that-is-at-least-32-characters"),
        accepted_handler,
    )

    assert result.status_code == 401
    assert result.body["error"]["code"] == "AUTH_FAILED"
    assert db_session.query(IntegrationEventLog).one().status == "REJECTED"


def test_invalid_hmac_is_rejected(db_session, integration_connection, service):
    result = run_request(
        service,
        db_session,
        make_request(event_payload(), signature="sha256=" + "0" * 64),
        accepted_handler,
    )

    assert result.status_code == 403
    assert result.body["error"]["code"] == "SIGNATURE_INVALID"


def test_expired_timestamp_is_rejected(db_session, integration_connection, service):
    expired = (datetime.now(timezone.utc) - timedelta(minutes=6)).isoformat().replace("+00:00", "Z")
    result = run_request(
        service,
        db_session,
        make_request(event_payload(), timestamp=expired),
        accepted_handler,
    )

    assert result.status_code == 403
    assert result.body["error"]["code"] == "TIMESTAMP_EXPIRED"


def test_reused_event_id_with_different_request_is_replay_attack(
    db_session,
    integration_connection,
    service,
):
    first = event_payload()
    second = event_payload(source_id="foundation_01ARZ3NDEKTSV4RRFFQ69G5FBZ")
    assert run_request(service, db_session, make_request(first), accepted_handler).status_code == 202

    result = run_request(service, db_session, make_request(second), accepted_handler)

    assert result.status_code == 409
    assert result.body["error"]["code"] == "REPLAY_DETECTED"


def test_exact_duplicate_event_returns_stored_response_once(
    db_session,
    integration_connection,
    service,
):
    calls = 0

    def handler(db, authenticated):
        nonlocal calls
        calls += 1
        return accepted_handler(db, authenticated)

    payload = event_payload()
    first = run_request(service, db_session, make_request(payload), handler)
    second = run_request(service, db_session, make_request(payload), handler)

    assert first.status_code == 202
    assert second.status_code == 200
    assert second.headers == {"Idempotency-Replayed": "true"}
    assert second.body == first.body
    assert calls == 1


def test_reused_idempotency_key_with_new_event_is_conflict(
    db_session,
    integration_connection,
    service,
):
    first = event_payload()
    second = event_payload(
        event_id="evt_01ARZ3NDEKTSV4RRFFQ69G5FBX",
        idempotency_key=first["idempotency_key"],
    )
    assert run_request(service, db_session, make_request(first), accepted_handler).status_code == 202

    result = run_request(service, db_session, make_request(second), accepted_handler)

    assert result.status_code == 409
    assert result.body["error"]["code"] == "IDEMPOTENCY_CONFLICT"


def test_api_key_cannot_access_unmapped_tenant(db_session, integration_connection, service):
    payload = event_payload()
    payload["tenant_id"] = "tenant_not_authorized"
    payload["idempotency_key"] = (
        f"tenant_not_authorized:{payload['event_name']}:{payload['source_id']}:v1"
    )
    result = run_request(
        service,
        db_session,
        make_request(payload, tenant_id="tenant_not_authorized"),
        accepted_handler,
    )

    assert result.status_code == 403
    assert result.body["error"]["code"] == "TENANT_NOT_RESOLVED"


def test_concurrent_duplicate_requests_execute_handler_once(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'integration-concurrency.db'}",
        connect_args={"check_same_thread": False, "timeout": 10},
    )
    session_factory = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    Base.metadata.create_all(engine)
    seed = session_factory()
    tenant = Tenant(
        id=uuid.uuid4(),
        legal_name="Concurrent Test Tenant",
        trade_name="Concurrent Test",
        financial_year_start=datetime.now().date(),
    )
    seed.add(tenant)
    seed.commit()
    create_connection(seed, tenant)
    seed.close()

    calls = 0
    calls_lock = threading.Lock()
    barrier = threading.Barrier(2)
    payload = event_payload()

    def execute():
        nonlocal calls
        db = session_factory()
        service = CartunezIntegrationService()
        barrier.wait()

        def handler(handler_db, authenticated):
            nonlocal calls
            with calls_lock:
                calls += 1
            time.sleep(0.1)
            return accepted_handler(handler_db, authenticated)

        try:
            return run_request(service, db, make_request(payload), handler)
        finally:
            db.close()

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: execute(), range(2)))

    assert sorted(result.status_code for result in results) == [200, 202]
    assert calls == 1
    verify = session_factory()
    assert verify.query(IntegrationReplayCache).count() == 1
    assert verify.query(IntegrationEventLog).count() == 2
    verify.close()
    engine.dispose()


def test_handler_exception_rolls_back_claim_and_business_changes(
    db_session,
    integration_connection,
    service,
):
    def failing_handler(db, authenticated):
        db.add(
            IntegrationEntityMap(
                tenant_id=authenticated.internal_tenant_id,
                integration_name="cartunez",
                entity_type="foundation_probe",
                external_id="external_probe",
                internal_id=uuid.uuid4(),
                sync_status="PENDING",
            )
        )
        db.flush()
        raise RuntimeError("simulated handler failure")

    result = run_request(service, db_session, make_request(event_payload()), failing_handler)

    assert result.status_code == 500
    assert result.body["error"]["code"] == "INTERNAL_ERROR"
    assert db_session.query(IntegrationEntityMap).count() == 0
    assert db_session.query(IntegrationReplayCache).count() == 0
    event_log = db_session.query(IntegrationEventLog).one()
    assert event_log.status == "FAILED"
