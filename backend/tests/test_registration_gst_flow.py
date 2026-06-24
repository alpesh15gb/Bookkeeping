"""
E2E VALIDATION: Registration → GST Invoice Flow
Verifies the auth.py fix for tax_mode auto-detection from GSTIN.

Tests:
1. Register tenant WITHOUT GSTIN → NON_GST, GST=0
2. Register tenant WITH GSTIN → GST_REGULAR, origin_state_code populated
3. Create contact, product, invoice → verify CGST/SGST (intrastate)
4. Create invoice with interstate POS → verify IGST
5. Verify ledger postings
6. Verify GSTR-1 totals
"""
import uuid
import unittest
from datetime import date
from decimal import Decimal
from fastapi.testclient import TestClient

import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product, Invoice,
    TenantSetting, JournalEntry, JournalLine, Account
)


class TestRegistrationGSTFlow(unittest.TestCase):
    """Fresh E2E validation of registration → GST invoice lifecycle."""

    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

    def _register(self, email, company_name, gstin=None):
        """Register a user and return (headers, tenant_id)."""
        payload = {
            "email": email,
            "password": "SecureP@ss123",
            "full_name": "Test User",
            "phone_number": "+919999999999",
            "company_legal_name": company_name,
        }
        if gstin:
            payload["company_gstin"] = gstin

        res = self.client.post("/api/v1/auth/register", json=payload)
        self.assertEqual(res.status_code, 201, f"Registration failed: {res.text}")

        login = self.client.post("/api/v1/auth/login", json={
            "email": email,
            "password": "SecureP@ss123"
        })
        self.assertEqual(login.status_code, 200, f"Login failed: {login.text}")
        token = login.json()["access_token"]

        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == email).first()
            membership = db.query(TenantMembership).filter(
                TenantMembership.user_id == user.id
            ).first()
            tenant_id = membership.tenant_id
        finally:
            db.close()

        headers = {
            "Authorization": f"Bearer {token}",
            "X-Tenant-ID": str(tenant_id)
        }
        return headers, tenant_id

    # ────────────────────────────────────────────────────────────
    # TEST 1: Register WITHOUT GSTIN → NON_GST
    # ────────────────────────────────────────────────────────────
    def test_register_without_gstin_creates_non_gst_tenant(self):
        headers, tenant_id = self._register(
            "nongst@test.com", "NonGST Corp"
        )

        db = SessionLocal()
        try:
            tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
            self.assertIsNone(tenant.gstin)
            self.assertEqual(tenant.tax_mode, "NON_GST")

            setting = db.query(TenantSetting).filter(
                TenantSetting.tenant_id == tenant_id
            ).first()
            self.assertIsNotNone(setting, "TenantSetting must be created during registration")
            self.assertFalse(setting.gst_enabled)
            self.assertIsNone(setting.origin_state_code)
        finally:
            db.close()

    # ────────────────────────────────────────────────────────────
    # TEST 2: Register WITH GSTIN → GST_REGULAR
    # ────────────────────────────────────────────────────────────
    def test_register_with_gstin_creates_gst_regular_tenant(self):
        # Maharashtra GSTIN: 27AAACT1234A1Z1
        headers, tenant_id = self._register(
            "gst@test.com", "GST Corp", gstin="27AAACT1234A1Z1"
        )

        db = SessionLocal()
        try:
            tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
            self.assertEqual(tenant.gstin, "27AAACT1234A1Z1")
            self.assertEqual(tenant.tax_mode, "GST_REGULAR")

            setting = db.query(TenantSetting).filter(
                TenantSetting.tenant_id == tenant_id
            ).first()
            self.assertIsNotNone(setting, "TenantSetting must be created during registration")
            self.assertTrue(setting.gst_enabled)
            self.assertEqual(setting.origin_state_code, "27",
                "origin_state_code must be derived from GSTIN prefix")
        finally:
            db.close()

    # ────────────────────────────────────────────────────────────
    # TEST 3: NON_GST tenant → invoice has zero GST
    # ────────────────────────────────────────────────────────────
    def test_non_gst_tenant_invoice_has_zero_gst(self):
        headers, tenant_id = self._register(
            "nongst_inv@test.com", "NonGST Invoice Corp"
        )

        # Create contact
        contact_res = self.client.post("/api/v1/masters/contacts", json={
            "name": "Test Customer",
            "contact_type": "CUSTOMER",
            "state_code": "27",
            "billing_address": {
                "street": "123 St", "city": "Mumbai",
                "state": "Maharashtra", "state_code": "27",
                "pincode": "400001", "country": "India"
            }
        }, headers=headers)
        self.assertEqual(contact_res.status_code, 201)
        contact_id = contact_res.json()["id"]

        # Create product
        prod_res = self.client.post("/api/v1/masters/products", json={
            "name": "Test Service",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 5000,
            "purchase_price": 0,
            "hsn_sac": "998314",
            "gst_rate": 18,
        }, headers=headers)
        self.assertEqual(prod_res.status_code, 201)
        product_id = prod_res.json()["id"]

        # Create invoice
        inv_res = self.client.post("/api/v1/invoices", json={
            "contact_id": contact_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": product_id,
                "quantity": 2,
                "rate": 5000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        }, headers=headers)
        self.assertEqual(inv_res.status_code, 201, f"Invoice creation failed: {inv_res.text}")
        inv = inv_res.json()

        # Verify GST is zero
        self.assertEqual(float(inv["cgst_amount"]), 0.0)
        self.assertEqual(float(inv["sgst_amount"]), 0.0)
        self.assertEqual(float(inv["igst_amount"]), 0.0)
        self.assertEqual(float(inv["total"]), 10000.0)
        self.assertEqual(float(inv["lines"][0]["gst_rate"]), 0.0)

    # ────────────────────────────────────────────────────────────
    # TEST 4: GST_REGULAR tenant → intrastate CGST+SGST
    # ────────────────────────────────────────────────────────────
    def test_gst_regular_intrastate_cgst_sgst(self):
        # Maharashtra GSTIN → origin_state = 27
        headers, tenant_id = self._register(
            "gst_intra@test.com", "IntraCorp", gstin="27AAACT1234A1Z1"
        )

        # Create contact in Maharashtra (same state)
        contact_res = self.client.post("/api/v1/masters/contacts", json={
            "name": "MH Customer",
            "contact_type": "CUSTOMER",
            "gstin": "27BBBBC5678D1Z2",
            "registration_type": "REGULAR",
            "state_code": "27",
            "billing_address": {
                "street": "1 St", "city": "Mumbai",
                "state": "Maharashtra", "state_code": "27",
                "pincode": "400001", "country": "India"
            }
        }, headers=headers)
        self.assertEqual(contact_res.status_code, 201)
        contact_id = contact_res.json()["id"]

        # Create product with 18% GST
        prod_res = self.client.post("/api/v1/masters/products", json={
            "name": "Dev Service",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 10000,
            "purchase_price": 0,
            "hsn_sac": "998314",
            "gst_rate": 18,
        }, headers=headers)
        self.assertEqual(prod_res.status_code, 201)
        product_id = prod_res.json()["id"]

        # Create intrastate invoice (POS = 27, same as origin)
        inv_res = self.client.post("/api/v1/invoices", json={
            "contact_id": contact_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": product_id,
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        }, headers=headers)
        self.assertEqual(inv_res.status_code, 201, f"Invoice failed: {inv_res.text}")
        inv = inv_res.json()

        # Verify CGST + SGST (intrastate)
        self.assertEqual(float(inv["lines"][0]["cgst_rate"]), 9.0)
        self.assertEqual(float(inv["lines"][0]["cgst_amount"]), 900.0)
        self.assertEqual(float(inv["lines"][0]["sgst_rate"]), 9.0)
        self.assertEqual(float(inv["lines"][0]["sgst_amount"]), 900.0)
        self.assertEqual(float(inv["lines"][0]["igst_rate"]), 0.0)
        self.assertEqual(float(inv["lines"][0]["igst_amount"]), 0.0)
        self.assertEqual(float(inv["cgst_amount"]), 900.0)
        self.assertEqual(float(inv["sgst_amount"]), 900.0)
        self.assertEqual(float(inv["total"]), 11800.0)

    # ────────────────────────────────────────────────────────────
    # TEST 5: GST_REGULAR tenant → interstate IGST
    # ────────────────────────────────────────────────────────────
    def test_gst_regular_interstate_igst(self):
        # Maharashtra GSTIN → origin_state = 27
        headers, tenant_id = self._register(
            "gst_inter@test.com", "InterCorp", gstin="27AAACT1234A1Z1"
        )

        # Create contact in Karnataka (different state)
        contact_res = self.client.post("/api/v1/masters/contacts", json={
            "name": "KA Customer",
            "contact_type": "CUSTOMER",
            "gstin": "29AAACI5678B2Z2",
            "registration_type": "REGULAR",
            "state_code": "29",
            "billing_address": {
                "street": "1 St", "city": "Bangalore",
                "state": "Karnataka", "state_code": "29",
                "pincode": "560001", "country": "India"
            }
        }, headers=headers)
        self.assertEqual(contact_res.status_code, 201)
        contact_id = contact_res.json()["id"]

        # Create product with 18% GST
        prod_res = self.client.post("/api/v1/masters/products", json={
            "name": "Dev Service",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 10000,
            "purchase_price": 0,
            "hsn_sac": "998314",
            "gst_rate": 18,
        }, headers=headers)
        self.assertEqual(prod_res.status_code, 201)
        product_id = prod_res.json()["id"]

        # Create interstate invoice (POS = 29, origin = 27)
        inv_res = self.client.post("/api/v1/invoices", json={
            "contact_id": contact_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29",
            "line_items": [{
                "product_id": product_id,
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        }, headers=headers)
        self.assertEqual(inv_res.status_code, 201, f"Invoice failed: {inv_res.text}")
        inv = inv_res.json()

        # Verify IGST (interstate)
        self.assertEqual(float(inv["lines"][0]["cgst_rate"]), 0.0)
        self.assertEqual(float(inv["lines"][0]["cgst_amount"]), 0.0)
        self.assertEqual(float(inv["lines"][0]["sgst_rate"]), 0.0)
        self.assertEqual(float(inv["lines"][0]["sgst_amount"]), 0.0)
        self.assertEqual(float(inv["lines"][0]["igst_rate"]), 18.0)
        self.assertEqual(float(inv["lines"][0]["igst_amount"]), 1800.0)
        self.assertEqual(float(inv["igst_amount"]), 1800.0)
        self.assertEqual(float(inv["total"]), 11800.0)

    # ────────────────────────────────────────────────────────────
    # TEST 6: Ledger postings exist for GST invoice
    # ────────────────────────────────────────────────────────────
    def test_gst_invoice_creates_ledger_postings(self):
        headers, tenant_id = self._register(
            "gst_ledger@test.com", "LedgerCorp", gstin="27AAACT1234A1Z1"
        )

        contact_res = self.client.post("/api/v1/masters/contacts", json={
            "name": "Ledger Customer",
            "contact_type": "CUSTOMER",
            "gstin": "27BBBBC5678D1Z2",
            "registration_type": "REGULAR",
            "state_code": "27",
            "billing_address": {
                "street": "1 St", "city": "Mumbai",
                "state": "Maharashtra", "state_code": "27",
                "pincode": "400001", "country": "India"
            }
        }, headers=headers)
        contact_id = contact_res.json()["id"]

        prod_res = self.client.post("/api/v1/masters/products", json={
            "name": "Dev Service",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 10000,
            "purchase_price": 0,
            "hsn_sac": "998314",
            "gst_rate": 18,
        }, headers=headers)
        product_id = prod_res.json()["id"]

        inv_res = self.client.post("/api/v1/invoices", json={
            "contact_id": contact_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": product_id,
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        }, headers=headers)
        self.assertEqual(inv_res.status_code, 201)
        inv_id = inv_res.json()["id"]

        db = SessionLocal()
        try:
            # Verify journal entry exists
            je = db.query(JournalEntry).filter(
                JournalEntry.source_type == "INVOICE",
                JournalEntry.source_id == uuid.UUID(inv_id),
            ).first()
            self.assertIsNotNone(je, "Journal entry must exist for invoice")

            # Verify journal lines
            lines = db.query(JournalLine).filter(
                JournalLine.entry_id == je.id
            ).all()

            # Collect debit and credit totals (JournalLine uses amount + direction)
            total_debit = sum(l.amount for l in lines if l.direction == "DEBIT")
            total_credit = sum(l.amount for l in lines if l.direction == "CREDIT")
            self.assertEqual(total_debit, total_credit,
                "Journal must balance (debits == credits)")

            credits_by_account = {}
            for l in lines:
                acct = db.query(Account).filter(Account.id == l.account_id).first()
                if l.direction == "CREDIT":
                    credits_by_account[acct.code] = float(l.amount)

            # Accounts use numeric codes; verify by known codes
            # 5001=sales_revenue, 3001=cgst_output, 3002=sgst_output
            self.assertIn("5001", credits_by_account)
            self.assertEqual(credits_by_account["5001"], 10000.0)
            self.assertIn("3001", credits_by_account)
            self.assertEqual(credits_by_account["3001"], 900.0)
            self.assertIn("3002", credits_by_account)
            self.assertEqual(credits_by_account["3002"], 900.0)
        finally:
            db.close()

    # ────────────────────────────────────────────────────────────
    # TEST 7: GSTR-1 totals match invoice
    # ────────────────────────────────────────────────────────────
    def test_gstr1_totals_match_invoice(self):
        headers, tenant_id = self._register(
            "gst_gstr1@test.com", "GSTR1Corp", gstin="27AAACT1234A1Z1"
        )

        contact_res = self.client.post("/api/v1/masters/contacts", json={
            "name": "GSTR1 Customer",
            "contact_type": "CUSTOMER",
            "gstin": "27BBBBC5678D1Z2",
            "registration_type": "REGULAR",
            "state_code": "27",
            "billing_address": {
                "street": "1 St", "city": "Mumbai",
                "state": "Maharashtra", "state_code": "27",
                "pincode": "400001", "country": "India"
            }
        }, headers=headers)
        contact_id = contact_res.json()["id"]

        prod_res = self.client.post("/api/v1/masters/products", json={
            "name": "Dev Service",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 10000,
            "purchase_price": 0,
            "hsn_sac": "998314",
            "gst_rate": 18,
        }, headers=headers)
        product_id = prod_res.json()["id"]

        # Create invoice
        inv_res = self.client.post("/api/v1/invoices", json={
            "contact_id": contact_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": product_id,
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        }, headers=headers)
        self.assertEqual(inv_res.status_code, 201)

        # Fetch GSTR-1
        gstr1_res = self.client.get("/api/v1/gst/gstr1", headers=headers)
        self.assertEqual(gstr1_res.status_code, 200)
        gstr1 = gstr1_res.json()

        # B2B section should have 1 invoice
        self.assertEqual(len(gstr1["b2b"]), 1)
        b2b = gstr1["b2b"][0]
        self.assertEqual(b2b["customer_gstin"], "27BBBBC5678D1Z2")
        self.assertEqual(float(b2b["taxable_value"]), 10000.0)
        self.assertEqual(float(b2b["cgst_amount"]), 900.0)
        self.assertEqual(float(b2b["sgst_amount"]), 900.0)

        # HSN summary should have 1 line
        self.assertEqual(len(gstr1["hsn_summary"]), 1)
        hsn = gstr1["hsn_summary"][0]
        self.assertEqual(hsn["hsn_sac"], "998314")
        self.assertEqual(float(hsn["taxable_value"]), 10000.0)


if __name__ == "__main__":
    unittest.main()
