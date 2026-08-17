"""
Purge company data — OTP-gated wipe (POST /api/v1/purge/request + verify).

Covers the contract the Settings -> Danger zone screen relies on:
  - request/verify full flow, with the dev-mode OTP fallback in the detail
  - wrong OTP rejected, and OTP is single-use (any attempt consumes it)
  - a successful purge wipes tenant-scoped data and recreates signup defaults
  - regression: when Redis is unreachable the endpoints must fall back to the
    in-process OTP cache instead of 500ing on a dead-but-truthy client
    (redis_client was assigned before ping() and never reset in the except).
  - regression: the append-only DB guards (apex_guard_*_delete from
    postgres_hardening) must not block the wipe; the purge transaction sets
    app.purge_tenant_id and the guards allow DELETE only for that tenant.
"""
import re
from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import delete, text

from src.infrastructure.database.idempotency import IdempotencyRecord
from src.infrastructure.database.models import (
    Account, Branch, Contact, FinancialYear, Invoice,
    JournalEntry, JournalLine, StockLedger,
)


# The exact append-only delete guards production runs (see
# src/core/postgres_hardening.apply_postgres_hardening). The unit-test DB is
# created with Base.metadata.create_all and skips hardening, so this test
# installs the guards itself to reproduce the production failure mode.
_GUARD_FUNCTIONS = [
    """CREATE OR REPLACE FUNCTION apex_guard_journal_entries_delete()
    RETURNS trigger AS $$
    BEGIN
        IF current_setting('app.purge_tenant_id', true) = OLD.tenant_id::text THEN
            RETURN OLD;
        END IF;
        RAISE EXCEPTION 'journal_entries is append-only accounting history and can never be deleted; create a reversal entry instead'
            USING ERRCODE = '55000';
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_catalog""",
    """CREATE OR REPLACE FUNCTION apex_guard_journal_lines_delete()
    RETURNS trigger AS $$
    BEGIN
        IF current_setting('app.purge_tenant_id', true) = OLD.tenant_id::text THEN
            RETURN OLD;
        END IF;
        RAISE EXCEPTION 'journal_lines is immutable accounting history and can never be deleted; create a reversal entry instead'
            USING ERRCODE = '55000';
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_catalog""",
    """CREATE OR REPLACE FUNCTION apex_guard_stock_ledger_delete()
    RETURNS trigger AS $$
    BEGIN
        IF current_setting('app.purge_tenant_id', true) = OLD.tenant_id::text THEN
            RETURN OLD;
        END IF;
        RAISE EXCEPTION 'stock_ledger is append-only inventory history; create a reversal movement instead'
            USING ERRCODE = '55000';
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_catalog""",
]

_GUARD_TRIGGERS = [
    "CREATE TRIGGER ck_journal_entries_no_delete BEFORE DELETE ON journal_entries FOR EACH ROW EXECUTE FUNCTION apex_guard_journal_entries_delete()",
    "CREATE TRIGGER ck_journal_lines_no_delete BEFORE DELETE ON journal_lines FOR EACH ROW EXECUTE FUNCTION apex_guard_journal_lines_delete()",
    "CREATE TRIGGER ck_stock_ledger_no_delete BEFORE DELETE ON stock_ledger FOR EACH ROW EXECUTE FUNCTION apex_guard_stock_ledger_delete()",
]


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


def test_purge_wipes_ledger_despite_append_only_guards(
    client, combined_headers, product_factory, db_session, tenant,
):
    """Regression: purge must wipe ledger history even though the DB guards
    forbid journal/stock deletes for every other path.

    Prod failure: POST /api/v1/purge/verify 500'd with
    'journal_lines is immutable accounting history and can never be deleted'
    because reset_company_to_signup_defaults deletes ledger rows while the
    apex_guard_*_delete triggers (no bypass) block them. The fix lets the
    purge transaction set a transaction-scoped app.purge_tenant_id flag that
    the guards honor only for the exact tenant being purged.
    """
    conn = db_session.connection()
    is_postgres = db_session.bind.dialect.name == "postgresql"
    if is_postgres:
        for stmt in _GUARD_FUNCTIONS:
            conn.execute(text(stmt))
        for stmt in _GUARD_TRIGGERS:
            conn.execute(text(stmt))
        db_session.commit()
    try:
        # Seed real accounting history: a balanced journal entry + lines and a
        # stock movement, all tenant-owned.
        product = product_factory(name="Purge Guard Product")
        account = Account(
            tenant_id=tenant.id, name="Purge Regression Asset",
            code="PURGE-ASSET", account_type="ASSET",
        )
        db_session.add(account)
        db_session.flush()
        entry = JournalEntry(
            id=uuid4(), tenant_id=tenant.id, entry_date=date.today(),
            reference_number="JE-PURGE-1", description="purge regression",
            source_type="INVOICE",
        )
        db_session.add(entry)
        db_session.flush()
        db_session.add_all([
            JournalLine(tenant_id=tenant.id, entry_id=entry.id, account_id=account.id,
                        amount=Decimal("100.00"), direction="DEBIT"),
            JournalLine(tenant_id=tenant.id, entry_id=entry.id, account_id=account.id,
                        amount=Decimal("100.00"), direction="CREDIT"),
        ])
        db_session.add(StockLedger(
            tenant_id=tenant.id, product_id=product.id, warehouse_id=None,
            quantity=Decimal("5.0000"), balance_quantity=Decimal("5.0000"),
            reference_type="INVOICE", reference_id=entry.id,
        ))
        db_session.commit()
        assert db_session.query(JournalLine).filter_by(tenant_id=tenant.id).count() >= 2
        assert db_session.query(StockLedger).filter_by(tenant_id=tenant.id).count() >= 1

        # With guards installed, a delete without the purge flag must still be
        # blocked (proves the bypass is narrow, not a blanket unlock). On
        # SQLite there are no DB guards, so this assertion only runs on
        # Postgres. Core delete -> DB trigger.
        if is_postgres:
            with pytest.raises(Exception, match="immutable accounting history"):
                db_session.execute(
                    delete(JournalLine.__table__).where(
                        JournalLine.__table__.c.tenant_id == tenant.id
                    )
                )
                db_session.commit()
            db_session.rollback()

        headers = combined_headers()
        r = client.post("/api/v1/purge/request", headers=headers)
        assert r.status_code == 200, r.text
        otp = _dev_otp(r)
        # The frontend sends an Idempotency-Key on mutations. Purge must not
        # create a claim: the wipe deletes the tenant's idempotency rows, and
        # the claim commit-marker would abort (IdempotencyClaimLostError) on
        # Postgres. The OTP is the purge's exactly-once guard instead.
        key = f"purge-regression-{uuid4().hex}"
        r = client.post(
            "/api/v1/purge/verify",
            json={"otp": otp},
            headers={**headers, "Idempotency-Key": key},
        )
        assert r.status_code == 200, r.text
        assert db_session.query(IdempotencyRecord).filter(
            IdempotencyRecord.idempotency_key == key,
            IdempotencyRecord.tenant_id == tenant.id,
        ).count() == 0

        # Ledger history is gone for the purged tenant.
        assert db_session.query(JournalEntry).filter_by(tenant_id=tenant.id).count() == 0
        assert db_session.query(JournalLine).filter_by(tenant_id=tenant.id).count() == 0
        assert db_session.query(StockLedger).filter_by(tenant_id=tenant.id).count() == 0
        # Signup defaults recreated, as in the non-guard purge test.
        assert db_session.query(Account).filter_by(tenant_id=tenant.id).count() > 0
        assert db_session.query(FinancialYear).filter_by(tenant_id=tenant.id).count() > 0
    finally:
        if is_postgres:
            for table, fn in [
                ("journal_entries", "apex_guard_journal_entries_delete"),
                ("journal_lines", "apex_guard_journal_lines_delete"),
                ("stock_ledger", "apex_guard_stock_ledger_delete"),
            ]:
                conn.execute(text(f"DROP TRIGGER IF EXISTS ck_{table}_no_delete ON {table}"))
                conn.execute(text(f"DROP FUNCTION IF EXISTS {fn}()"))
            db_session.commit()
