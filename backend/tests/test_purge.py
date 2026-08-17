"""
Purge company data — OTP-gated wipe (POST /api/v1/purge/request + verify).

Covers the contract the Settings -> Danger zone screen relies on:
  - request/verify full flow, with the dev-mode OTP fallback in the detail
  - wrong OTP rejected, and OTP is single-use (any attempt consumes it)
  - a successful purge wipes tenant-scoped data and recreates signup defaults
  - regression: when Redis is unreachable the endpoints must fall back to the
    in-process OTP cache instead of 500ing on a dead-but-truthy client
    (redis_client was assigned before ping() and never reset in the except).
"""
import re

from src.infrastructure.database.models import (
    Account, Branch, Contact, FinancialYear, Invoice,
)


def _dev_otp(response) -> str:
    match = re.search(r"OTP code: (\d{6})", response.json().get("detail", ""))
    assert match, f"no dev OTP in response: {response.text}"
    return match.group(1)


def test_purge_request_requires_auth(client, tenant_headers):
    r = client.post("/api/v1/purge/request", headers=tenant_headers)
    assert r.status_code in (401, 403)


def test_purge_full_flow(client, combined_headers, contact_factory,
                         product_factory, invoice_factory, db_session):
    # Seed tenant data that must be wiped by the purge.
    contact_factory(name="Purge Me Customer")
    product_factory(name="Purge Me Product")
    invoice_factory(status="POSTED")
    assert db_session.query(Contact).count() >= 1
    assert db_session.query(Invoice).count() >= 1

    headers = combined_headers()

    # Request the OTP. Dev mode has no SMTP, so the endpoint returns the OTP
    # in the detail — this is also the Redis-unreachable fallback path, which
    # used to 500 here (dead redis_client staying truthy).
    r = client.post("/api/v1/purge/request", headers=headers)
    assert r.status_code == 200, r.text
    otp1 = _dev_otp(r)

    # Wrong OTP is rejected and consumes the OTP (single-use semantics).
    r = client.post("/api/v1/purge/verify", json={"otp": "000000"}, headers=headers)
    assert r.status_code == 400, r.text
    r = client.post("/api/v1/purge/verify", json={"otp": otp1}, headers=headers)
    assert r.status_code == 400, r.text

    # Fresh OTP: the correct code wipes everything and recreates defaults.
    r = client.post("/api/v1/purge/request", headers=headers)
    assert r.status_code == 200, r.text
    otp2 = _dev_otp(r)
    r = client.post("/api/v1/purge/verify", json={"otp": otp2}, headers=headers)
    assert r.status_code == 200, r.text

    # Tenant data is gone…
    assert db_session.query(Contact).count() == 0
    assert db_session.query(Invoice).count() == 0
    # …and signup defaults were recreated.
    assert db_session.query(Account).count() > 0
    assert db_session.query(FinancialYear).count() > 0
    assert db_session.query(Branch).count() > 0

    # Replaying the used OTP must fail.
    r = client.post("/api/v1/purge/verify", json={"otp": otp2}, headers=headers)
    assert r.status_code == 400, r.text
