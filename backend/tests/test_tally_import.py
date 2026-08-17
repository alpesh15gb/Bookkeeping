"""Regression tests for the Tally XML importer.

The importer previously 500'd on every real export because of four latent
bugs: it instantiated the static-only NumberingSeriesService, passed string
dates to date columns, passed read-only ``product_name`` properties into
InvoiceLine/BillLine, and used a nonexistent ``reference`` kwarg on
Payment/BillPayment. These tests drive the endpoint end-to-end with a
realistic Tally export.
"""
import os
import unittest
from datetime import date
from pathlib import Path

from fastapi.testclient import TestClient

import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import Base, engine

SAMPLE = Path(__file__).resolve().parent.parent / "tools" / "test_tally_sample.xml"


class TestTallyImport(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        reg = {
            "email": "tally@company.com",
            "password": "SecurePassword123!",
            "full_name": "Tally User",
            "phone_number": "+919999988889",
            "company_legal_name": "Tally Co Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A",
        }
        self.client.post("/api/v1/auth/register", json=reg)
        login = self.client.post("/api/v1/auth/login", json={
            "email": reg["email"], "password": reg["password"],
        }).json()
        self.headers = {"Authorization": f"Bearer {login['access_token']}"}

        from src.core.database import SessionLocal
        from src.infrastructure.database.models import User, TenantMembership
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == reg["email"]).first()
            tenant_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user.id).first().tenant_id
        finally:
            db.close()
        self.headers["X-Tenant-ID"] = str(tenant_id)

    def _import(self):
        with open(SAMPLE, "rb") as fh:
            return self.client.post(
                "/api/v1/tally/import",
                files={"file": ("export.xml", fh.read(), "application/xml")},
                headers=self.headers,
            )

    def test_tally_import_succeeds_and_maps_documents(self):
        res = self._import()
        self.assertEqual(res.status_code, 200, res.text)
        summary = res.json()
        self.assertEqual(summary["contacts_imported"], 2)
        self.assertEqual(summary["products_imported"], 1)
        self.assertEqual(summary["invoices_imported"], 1)
        self.assertEqual(summary["bills_imported"], 1)
        self.assertEqual(summary["payments_imported"], 1)

    def test_tally_import_posts_correct_totals_and_dates(self):
        res = self._import()
        self.assertEqual(res.status_code, 200, res.text)

        from src.core.database import SessionLocal
        from src.infrastructure.database.models import Invoice, Bill, Payment, InvoiceLine
        db = SessionLocal()
        try:
            inv = db.query(Invoice).first()
            self.assertIsNotNone(inv)
            # 10000 + 900 CGST + 900 SGST = 11800
            self.assertEqual(float(inv.total), 11800.00)
            self.assertEqual(float(inv.cgst_amount), 900.00)
            self.assertEqual(float(inv.sgst_amount), 900.00)
            # Dates must be real dates, not strings (20260115 -> 2026-01-15)
            self.assertEqual(inv.issue_date, date(2026, 1, 15))
            line = db.query(InvoiceLine).filter(InvoiceLine.invoice_id == inv.id).first()
            self.assertIsNotNone(line)
            # product_name is a read-only property; the name must land in description
            self.assertEqual(line.description, "Steel Rods")

            bill = db.query(Bill).first()
            self.assertIsNotNone(bill)
            # 4000 + 360 + 360 = 4720
            self.assertEqual(float(bill.total), 4720.00)
            self.assertEqual(bill.issue_date, date(2026, 1, 20))

            pay = db.query(Payment).first()
            self.assertIsNotNone(pay)
            self.assertEqual(float(pay.amount), 5000.00)
            # reference must land in reference_number (the model column)
            self.assertEqual(pay.reference_number, "RC-3001")
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
