"""
DEVELOPMENT / TEST TOOLING — NOT part of the production runtime.

seed_draft_review_sample.py — create sample data for the Draft Review Report.

Creates a tenant, a user + membership, contacts, accounts, and a handful of
DRAFT invoices/bills plus one posted bill, so scripts/review_ledger_drafts.py
can be exercised end-to-end. Only writes to the DB given by DATABASE_URL;
intended for local/CI use against scratch databases, never production data.

Usage:
    DATABASE_URL=sqlite:///./draft_review_sample.db python scripts/seed_draft_review_sample.py
"""
import os
import sys
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from src.infrastructure.database import models as M

# NOTE: sample UUIDs deliberately contain hex letters (a-f). All-digit UUIDs
# (e.g. 11111111-...) are stored as REAL by SQLite's NUMERIC affinity on the
# `UUID` column type, which would corrupt the demo data.
TENANT_ID = uuid.UUID("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1")
USER_ID = uuid.UUID("b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2")
CUSTOMER_ID = uuid.UUID("c3c3c3c3-c3c3-c3c3-c3c3-c3c3c3c3c3c3")
VENDOR_ID = uuid.UUID("d4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4")
CUSTOMER_ACCT = uuid.UUID("e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5")
VENDOR_ACCT = uuid.UUID("f6f6f6f6-f6f6-f6f6-f6f6-f6f6f6f6f6f6")
REVENUE_ACCT = uuid.UUID("a1b2c3d4-a1b2-c3d4-a1b2-c3d4a1b2c3d4")
CASH_ACCT = uuid.UUID("b1c2d3e4-b1c2-d3e4-b1c2-d3e4b1c2d3e4")
JOURNAL_ACCT = uuid.UUID("c1d2e3f4-c1d2-e3f4-c1d2-e3f4c1d2e3f4")

INV_DRAFT = uuid.UUID("aaaaaaaa-0000-0000-0000-000000000001")
INV_BROKEN = uuid.UUID("abababab-0000-0000-0000-000000000002")
BILL_DRAFT = uuid.UUID("bbbbbbbb-0000-0000-0000-000000000001")
BILL_POSTED = uuid.UUID("bcbcbcbc-0000-0000-0000-000000000002")
JE_POSTED = uuid.UUID("cdcdcdcd-0000-0000-0000-000000000001")


def main() -> None:
    db_url = os.environ.get("DATABASE_URL", "sqlite:///./draft_review_sample.db")
    engine = create_engine(db_url)
    now = datetime.now(timezone.utc)
    with Session(engine) as db:
        if db.query(M.Tenant).filter(M.Tenant.id == TENANT_ID).first():
            print(f"Already seeded: {db_url}")
            return

        db.add(M.Tenant(
            id=TENANT_ID,
            legal_name="Sample Co Pvt Ltd",
            trade_name="Sample Co",
            gstin="27AAACS1234F1Z5",
            tax_mode="REGULAR",
            financial_year_start=date(2026, 4, 1),
        ))
        db.add(M.User(
            id=USER_ID,
            email="owner@sample.com",
            full_name="Owner",
            password_hash="x",
            is_active=True,
        ))
        db.add(M.TenantMembership(tenant_id=TENANT_ID, user_id=USER_ID, role="OWNER"))
        db.add(M.FinancialYear(
            tenant_id=TENANT_ID, name="2026-27",
            start_date=date(2026, 4, 1), end_date=date(2027, 3, 31),
            status="CURRENT", is_current=True,
        ))
        db.add(M.Contact(id=CUSTOMER_ID, tenant_id=TENANT_ID, name="Acme Retail", contact_type="CUSTOMER"))
        db.add(M.Contact(id=VENDOR_ID, tenant_id=TENANT_ID, name="Supply Mart", contact_type="VENDOR"))
        db.add_all([
            M.Account(id=CUSTOMER_ACCT, tenant_id=TENANT_ID, name="Acme Retail", code="1200",
                      account_type="ASSET", account_group="Receivables"),
            M.Account(id=VENDOR_ACCT, tenant_id=TENANT_ID, name="Supply Mart", code="2200",
                      account_type="LIABILITY", account_group="Payables"),
            M.Account(id=REVENUE_ACCT, tenant_id=TENANT_ID, name="Sales Revenue", code="4000",
                      account_type="REVENUE", account_group="Revenue"),
            M.Account(id=CASH_ACCT, tenant_id=TENANT_ID, name="Cash on Hand", code="1001",
                      account_type="ASSET", account_group="Cash & Bank"),
            M.Account(id=JOURNAL_ACCT, tenant_id=TENANT_ID, name="Sample Journal Account", code="9999",
                      account_type="ASSET", account_group="Other Current Assets"),
        ])

        # Draft invoice (no journal) — should be POST
        db.add(M.Invoice(
            id=INV_DRAFT,
            tenant_id=TENANT_ID,
            contact_id=CUSTOMER_ID,
            invoice_number="INV-2026-0001",
            issue_date=date(2026, 6, 1),
            due_date=date(2026, 7, 1),
            status="DRAFT",
            pos_state_code="27",
            subtotal=Decimal("10000.0000"),
            total=Decimal("10000.0000"),
            created_by=USER_ID,
            lines=[
                M.InvoiceLine(
                    description="Consulting services", quantity=Decimal("1"),
                    rate=Decimal("10000.0000"), subtotal=Decimal("10000.0000"),
                    total=Decimal("10000.0000"), hsn_sac="998313", gst_rate=Decimal("0"),
                ),
            ],
        ))
        # Draft invoice with NO line items — should be REVIEW (validation problem:
        # the DB header CHECK forces total = subtotal + taxes, so a zero-total
        # invoice cannot exist; the report instead flags missing lines).
        db.add(M.Invoice(
            id=INV_BROKEN,
            tenant_id=TENANT_ID,
            contact_id=CUSTOMER_ID,
            invoice_number="INV-2026-0002",
            issue_date=date(2026, 6, 2),
            due_date=date(2026, 7, 2),
            status="DRAFT",
            pos_state_code="27",
            subtotal=Decimal("5000.0000"),
            total=Decimal("5000.0000"),
            created_by=USER_ID,
        ))
        # Draft bill — should be POST
        db.add(M.Bill(
            id=BILL_DRAFT,
            tenant_id=TENANT_ID,
            contact_id=VENDOR_ID,
            bill_number="BILL-2026-0001",
            issue_date=date(2026, 6, 3),
            due_date=date(2026, 7, 3),
            status="DRAFT",
            pos_state_code="27",
            subtotal=Decimal("8000.0000"),
            total=Decimal("8000.0000"),
            created_by=USER_ID,
            lines=[
                M.BillLine(
                    description="Office supplies", quantity=Decimal("2"),
                    rate=Decimal("4000.0000"), subtotal=Decimal("8000.0000"),
                    total=Decimal("8000.0000"), hsn_sac="39269099", gst_rate=Decimal("0"),
                ),
            ],
        ))
        # Posted bill — skipped by the report (not DRAFT)
        posted_bill = M.Bill(
            id=BILL_POSTED,
            tenant_id=TENANT_ID,
            contact_id=VENDOR_ID,
            bill_number="BILL-2026-0002",
            issue_date=date(2026, 6, 4),
            due_date=date(2026, 7, 4),
            status="UNPAID",
            pos_state_code="27",
            subtotal=Decimal("12000.0000"),
            total=Decimal("12000.0000"),
            created_by=USER_ID,
        )
        db.add(posted_bill)
        db.flush()
        # Journal entry for the posted bill
        db.add(M.JournalEntry(
            id=JE_POSTED,
            tenant_id=TENANT_ID,
            entry_date=date(2026, 6, 4),
            reference_number="BILL-2026-0002",
            description="Ledger posting for vendor bill BILL-2026-0002",
            source_type="BILL",
            source_id=posted_bill.id,
            created_by=USER_ID,
            posted_by=USER_ID,
            posted_at=now,
            source_channel="API",
            lines=[
                M.JournalLine(account_id=VENDOR_ACCT, amount=Decimal("12000.0000"), direction="CREDIT"),
                M.JournalLine(account_id=JOURNAL_ACCT, amount=Decimal("12000.0000"), direction="DEBIT"),
            ],
        ))
        db.commit()
    print(f"Seeded {db_url}")


if __name__ == "__main__":
    main()
