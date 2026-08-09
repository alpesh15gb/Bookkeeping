"""Mandatory Idempotency-Key on financial creates and corrections.

Save/Edit/Delete can create ledger or stock facts.  They must therefore be
retry-safe, while read-like preview POSTs must not require a key.
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


def _assert_required(response):
    assert response.status_code == 428, response.text
    assert response.json()["code"] == "IDEMPOTENCY_KEY_REQUIRED"


def test_financial_creates_require_key(client):
    paths = (
        "/api/v1/invoices",
        "/api/v1/bills",
        "/api/v1/expenses",
        "/api/v1/inventory-adjustments",
        "/api/v1/payments/receipts",
        "/api/v1/payments/disbursements",
        "/api/v1/accounting/journals",
        "/api/v1/accounting/contra",
        "/api/v1/invoices/credit-notes",
        "/api/v1/invoices/debit-notes",
        "/api/v1/returns/sales",
        "/api/v1/returns/purchase",
    )
    for path in paths:
        _assert_required(client.post(path, json={}))


def test_edit_and_delete_corrections_require_key(client):
    resource_id = uuid.uuid4()
    paths = (
        f"/api/v1/invoices/{resource_id}",
        f"/api/v1/bills/{resource_id}",
        f"/api/v1/expenses/{resource_id}",
        f"/api/v1/inventory-adjustments/{resource_id}",
        f"/api/v1/invoices/credit-notes/{resource_id}",
        f"/api/v1/invoices/debit-notes/{resource_id}",
        f"/api/v1/payments/receipts/{resource_id}",
        f"/api/v1/payments/disbursements/{resource_id}",
        f"/api/v1/returns/sales/{resource_id}",
        f"/api/v1/returns/purchase/{resource_id}",
        f"/api/v1/accounting/journals/{resource_id}",
    )
    for path in paths:
        _assert_required(client.put(path, json={}))
        _assert_required(client.delete(path))


def test_preview_posts_do_not_require_idempotency_key(client):
    for path in (
        "/api/v1/invoices/preview",
        "/api/v1/bills/preview",
        "/api/v1/expenses/preview",
    ):
        response = client.post(path, json={})
        assert response.status_code != 428, (path, response.text)


def test_with_key_passes_through_to_normal_request_processing(client):
    # The key itself is accepted.  With a bogus tenant the normal auth/tenant
    # or payload validation may still reject the request, but not with 428.
    response = client.post(
        "/api/v1/invoices",
        json={},
        headers={
            "Idempotency-Key": str(uuid.uuid4()),
            "X-Tenant-ID": str(uuid.uuid4()),
        },
    )
    assert response.status_code != 428, response.text


def test_non_financial_post_does_not_require_key(client):
    response = client.post(
        "/api/v1/auth/login",
        json={"email": "x@example.com", "password": "x"},
    )
    assert response.status_code != 428
