"""
Regression tests for imported-document ledger posting.

Two connected defects shipped together:
  1. The legacy importers created invoices/bills/payments in their final
     statuses but never posted journal entries (the Vyapar auto-post guard
     only matched statuses the importer never assigns), so imports landed
     with an empty ledger — day book, P&L, trial balance and balance sheet
     showed nothing even though documents existed.
  2. There was no repair path: the frontend's "Post documents to ledger"
     button called /api/v1/import/backfill-postings, which did not exist.

Fixed by state-preserving, idempotent posting at import time
(src/domains/accounting/backfill_posting.py) plus the backfill endpoint
(src/api/v1/backfill.py).  Posting never touches document status,
amount_paid, allocations or stock, and sub-paisa round-off dust (e.g. 0.0024)
is recomputed to the real paise residual instead of producing invalid 0.00
journal lines.
"""
import os
import sys
import unittest
from datetime import date, timedelta
from decimal import Decimal

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fastapi.testclient import TestClient

from src.core.database import Base, SessionLocal, engine
from src.main import app

SAMPLE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "tools", "test_tally_sample.xml"))


class _Base(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)
        reg = {
            "email": "backfill@company.com",
            "password": "SecurePassword123!",
            "full_name": "Backfill User",
            "phone_number": "+919999988889",
            "company_legal_name": "Backfill Co Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A",
        }
        self.client.post("/api/v1/auth/register", json=reg)
        login = self.client.post("/api/v1/auth/login", json={
            "email": reg["email"], "password": reg["password"],
        }).json()
        self.headers = {"Authorization": f"Bearer {login['access_token']}"}
        db = SessionLocal()
        try:
            from src.infrastructure.database.models import TenantMembership, User
            user = db.query(User).filter(User.email == reg["email"]).first()
            self.tenant_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user.id).first().tenant_id
        finally:
            db.close()
        self.headers["X-Tenant-ID"] = str(self.tenant_id)

    def _journal_counts(self):
        from src.infrastructure.database.models import JournalEntry
        db = SessionLocal()
        try:
            rows = (
                db.query(JournalEntry.source_type, JournalEntry.source_id)
                .filter(JournalEntry.tenant_id == self.tenant_id)
                .all()
            )
            return {
                "INVOICE": sum(1 for st, _ in rows if st == "INVOICE"),
                "BILL": sum(1 for st, _ in rows if st == "BILL"),
                "PAYMENT": sum(1 for st, _ in rows if st == "PAYMENT"),
            }
        finally:
            db.close()

    def _delete_journals(self):
        from src.infrastructure.database.models import JournalEntry
        db = SessionLocal()
        try:
            db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_id).delete(synchronize_session=False)
            db.commit()
        finally:
            db.close()


class TestImporterPostsLedger(_Base):
    def test_tally_import_posts_invoice_bill_and_payment(self):
        with open(SAMPLE, "rb") as fh:
            res = self.client.post(
                "/api/v1/tally/import",
                files={"file": ("export.xml", fh.read(), "application/xml")},
                headers=self.headers,
            )
        self.assertEqual(res.status_code, 200, res.text)
        counts = self._journal_counts()
        # Regression: before the fix the importer created the documents but
        # zero journal entries, leaving the ledger empty.
        self.assertEqual(counts["INVOICE"], 1)
        self.assertEqual(counts["BILL"], 1)
        self.assertEqual(counts["PAYMENT"], 1)

    def test_backfill_requires_auth(self):
        res = self.client.post(
            "/api/v1/import/backfill-postings",
            headers={"X-Tenant-ID": str(self.tenant_id)},
        )
        self.assertIn(res.status_code, (401, 403))


class TestBackfillEndpoint(_Base):
    def test_backfill_restores_missing_postings_idempotently(self):
        with open(SAMPLE, "rb") as fh:
            res = self.client.post(
                "/api/v1/tally/import",
                files={"file": ("export.xml", fh.read(), "application/xml")},
                headers=self.headers,
            )
        self.assertEqual(res.status_code, 200, res.text)
        before = self._journal_counts()

        # Simulate a pre-fix tenant: ledger wiped, documents untouched.
        self._delete_journals()
        self.assertEqual(self._journal_counts(), {"INVOICE": 0, "BILL": 0, "PAYMENT": 0})

        res = self.client.post("/api/v1/import/backfill-postings", headers=self.headers)
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["invoices_posted"], before["INVOICE"], data)
        self.assertEqual(data["bills_posted"], before["BILL"], data)
        self.assertEqual(data["customer_payments_posted"], 1, data)
        self.assertEqual(data["errors"], [], data["errors"])

        # Document state untouched by the backfill.
        from src.infrastructure.database.models import Bill, Invoice, Payment
        db = SessionLocal()
        try:
            inv = db.query(Invoice).first()
            bill = db.query(Bill).first()
            pay = db.query(Payment).first()
            self.assertEqual(float(inv.total), 11800.00)
            self.assertEqual(float(bill.total), 4720.00)
            self.assertEqual(float(pay.amount), 5000.00)
            self.assertEqual(pay.status, "ACTIVE")
        finally:
            db.close()

        # Idempotent: a second run posts nothing.
        res = self.client.post("/api/v1/import/backfill-postings", headers=self.headers)
        data2 = res.json()
        self.assertEqual(data2["invoices_posted"], 0)
        self.assertEqual(data2["bills_posted"], 0)
        self.assertEqual(data2["invoices_skipped"], before["INVOICE"])


class TestPostingHelpers(_Base):
    def test_round_off_dust_posts_cleanly_and_balances(self):
        """Sub-paisa round-off must produce a paise residual, never a 0.00 line."""
        from src.infrastructure.database.models import (
            Contact, Invoice, JournalEntry, JournalLine,
        )
        db = SessionLocal()
        try:
            contact = Contact(
                tenant_id=self.tenant_id,
                name="Round Off Customer",
                email="ro@test.com",
                phone="+919876543210",
                contact_type="CUSTOMER",
                gstin="27AACTC1234A1Z5",
                state_code="27",
            )
            db.add(contact)
            db.flush()
            subtotal = Decimal("3347.4576")
            cgst = Decimal("301.27")
            sgst = Decimal("301.27")
            invoice = Invoice(
                tenant_id=self.tenant_id,
                contact_id=contact.id,
                invoice_number="RO-1",
                issue_date=date.today(),
                due_date=date.today() + timedelta(days=15),
                status="POSTED",
                subtotal=subtotal,
                discount_total=Decimal("0"),
                cgst_amount=cgst,
                sgst_amount=sgst,
                igst_amount=Decimal("0"),
                utgst_amount=Decimal("0"),
                cess_amount=Decimal("0"),
                round_off=Decimal("0.0024"),  # sub-paisa dust from legacy data
                shipping_charges=Decimal("0"),
                total=Decimal("3950.0000"),
                amount_paid=Decimal("0"),
                pos_state_code="27",
                e_invoice_status="PENDING",
            )
            db.add(invoice)
            db.flush()
            inv_id = invoice.id

            from src.domains.accounting.backfill_posting import post_invoice_if_missing
            post_invoice_if_missing(db, self.tenant_id, invoice)
            db.commit()
        finally:
            db.close()

        db = SessionLocal()
        try:
            je = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.source_type == "INVOICE",
            ).first()
            self.assertIsNotNone(je)
            lines = db.query(JournalLine).filter(JournalLine.entry_id == je.id).all()
            self.assertTrue(all(line.amount > 0 for line in lines), "0.00 lines rejected")
            debit = sum(l.amount for l in lines if l.direction == "DEBIT")
            credit = sum(l.amount for l in lines if l.direction == "CREDIT")
            self.assertAlmostEqual(float(debit), float(credit), places=2)
            self.assertAlmostEqual(float(debit), 3950.00, places=2)

            # Re-run is idempotent (no duplicate posting).
            from src.domains.accounting.backfill_posting import post_invoice_if_missing
            try:
                post_invoice_if_missing(db, self.tenant_id,
                                        db.query(Invoice).get(inv_id))
                self.fail("expected duplicate-posting guard to raise")
            except ValueError:
                pass
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
