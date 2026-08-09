"""Mandatory Idempotency-Key on critical financial mutation endpoints.

Production requires an Idempotency-Key on POST /api/v1/invoices, /bills,
/payments and /accounting/journals so a client retry can never double-post a
financial transaction.  The main regression suite runs with the flag off
(those tests predate the rule); these tests exercise the enforcement itself.
"""

import uuid

import pytest
from fastapi.testclient import TestClient

from src.main import app
from src.core.config import settings


@pytest.fixture()
def client():
    previous = settings.REQUIRE_IDEMPOTENCY_KEY
    settings.REQUIRE_IDEMPOTENCY_KEY = True
    with TestClient(app) as test_client:
        yield test_client
    settings.REQUIRE_IDEMPOTENCY_KEY = previous


def test_invoice_post_without_key_is_refused(client):
    resp = client.post("/api/v1/invoices", json={})
    assert resp.status_code == 428, resp.text
    assert resp.json()["code"] == "IDEMPOTENCY_KEY_REQUIRED"


def test_bill_post_without_key_is_refused(client):
    resp = client.post("/api/v1/bills", json={})
    assert resp.status_code == 428, resp.text


def test_payment_post_without_key_is_refused(client):
    resp = client.post("/api/v1/payments", json={})
    assert resp.status_code == 428, resp.text


def test_journal_post_without_key_is_refused(client):
    resp = client.post("/api/v1/accounting/journals", json={})
    assert resp.status_code == 428, resp.text


def test_with_key_passes_through_to_validation(client):
    # The middleware accepts the request (key present); the endpoint still
    # validates the payload (empty body -> 4xx from the schema, not 428).
    resp = client.post(
        "/api/v1/invoices",
        json={},
        headers={"Idempotency-Key": str(uuid.uuid4()), "X-Tenant-ID": str(uuid.uuid4())},
    )
    assert resp.status_code != 428, resp.text


def test_non_financial_post_does_not_require_key(client):
    # Non-financial POSTs (e.g. auth) are not mandatory-idempotency.
    resp = client.post("/api/v1/auth/login", json={"email": "x@example.com", "password": "x"})
    assert resp.status_code != 428
