import sys
import os
import uuid
import unittest
from datetime import date
from decimal import Decimal
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product, Invoice, Bill, CreditNote, BankingProfile
)

class TestGSTCompliance(unittest.TestCase):
    def setUp(self):
        # Reset database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # 1. Register Tenant A
        reg_payload_a = {
            "email": "owner_a@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma A",
            "phone_number": "+919999988881",
            "company_legal_name": "Tenant A Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A"
        }
        self.client.post("/api/v1/auth/register", json=reg_payload_a)
        login_a = self.client.post("/api/v1/auth/login", json={
            "email": "owner_a@company.com",
            "password": "SecurePassword123!"
        }).json()
        self.token_a = login_a["access_token"]

        # 2. Register Tenant B
        reg_payload_b = {
            "email": "owner_b@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma B",
            "phone_number": "+919999988882",
            "company_legal_name": "Tenant B Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z2",
            "company_pan": "BBBBB2222B"
        }
        self.client.post("/api/v1/auth/register", json=reg_payload_b)
        login_b = self.client.post("/api/v1/auth/login", json={
            "email": "owner_b@company.com",
            "password": "SecurePassword123!"
        }).json()
        self.token_b = login_b["access_token"]

        # Retrieve tenant IDs and seed Master Data
        db = SessionLocal()
        try:
            m_a = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_a@company.com").first().id).first()
            self.tenant_a_id = m_a.tenant_id

            m_b = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_b@company.com").first().id).first()
            self.tenant_b_id = m_b.tenant_id

            # Seed bank details for Tenant A
            bank_a = BankingProfile(
                tenant_id=self.tenant_a_id,
                bank_name="HDFC Bank",
                account_number="50001002003004",
                ifsc_code="HDFC0000001",
                account_holder_name="Tenant A Pvt Ltd",
                is_primary=True,
                is_active=True
            )

            # Customer 1 (B2B - Registered)
            self.customer_b2b = Contact(
                id=uuid.UUID("11111111-1111-1111-1111-11111111111a"),
                tenant_id=self.tenant_a_id,
                name="Registered Corp",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={"street": "1, GSTR-1 St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True
            )

            # Customer 2 (B2C - Unregistered)
            self.customer_b2c = Contact(
                id=uuid.UUID("22222222-2222-2222-2222-22222222222a"),
                tenant_id=self.tenant_a_id,
                name="Individual Consumer",
                contact_type="CUSTOMER",
                gstin=None,
                pan=None,
                registration_type="CONSUMER",
                billing_address={"street": "2, B2CS St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True
            )

            # Vendor (Registered)
            self.vendor_b2b = Contact(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333b"),
                tenant_id=self.tenant_a_id,
                name="Supplier Pvt Ltd",
                contact_type="VENDOR",
                gstin="29AAACI5678B2Z2",
                pan="AAACI5678B",
                registration_type="REGULAR",
                billing_address={"street": "3, Supplier Rd", "city": "Bengaluru", "state": "Karnataka", "state_code": "29", "pincode": "560100", "country": "India"},
                state_code="29",
                is_active=True
            )

            # Product (Goods)
            self.product_a = Product(
                id=uuid.UUID("44444444-4444-4444-4444-44444444444c"),
                tenant_id=self.tenant_a_id,
                name="Accounting Software License",
                sku="SRV-ACC-LIC",
                hsn_sac="85238020",
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("10000.00"),
                purchase_price=Decimal("5000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )

            db.add_all([bank_a, self.customer_b2b, self.customer_b2c, self.vendor_b2b, self.product_a])
            db.commit()

            db.refresh(self.customer_b2b)
            db.refresh(self.customer_b2c)
            db.refresh(self.vendor_b2b)
            db.refresh(self.product_a)

            self.customer_b2b_id = self.customer_b2b.id
            self.customer_b2c_id = self.customer_b2c.id
            self.vendor_b2b_id = self.vendor_b2b.id
            self.product_id = self.product_a.id
        finally:
            db.close()

        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a_id),
            "Authorization": f"Bearer {self.token_a}"
        }
        self.headers_b = {
            "X-Tenant-ID": str(self.tenant_b_id),
            "Authorization": f"Bearer {self.token_b}"
        }

    def test_gstr1_returns_compilation(self):
        # 1. Post and finalize B2B sales invoice (subtotal = 10000, CGST = 900, SGST = 900)
        inv1_payload = {
            "contact_id": str(self.customer_b2b_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "85238020",
                    "gst_rate": 18.0
                }
            ]
        }
        inv1 = self.client.post("/api/v1/invoices", json=inv1_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/invoices/{inv1['id']}/finalize", headers=self.headers_a)

        # 2. Post and finalize B2C Small sales invoice (unregistered customer, pos state "27", total < 2.5L)
        inv2_payload = {
            "contact_id": str(self.customer_b2c_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "85238020",
                    "gst_rate": 18.0
                }
            ]
        }
        inv2 = self.client.post("/api/v1/invoices", json=inv2_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/invoices/{inv2['id']}/finalize", headers=self.headers_a)

        # 3. Post and finalize B2C Large sales invoice (unregistered customer, inter-state POS "29", total 2.95L > 2.5L)
        inv3_payload = {
            "contact_id": str(self.customer_b2c_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29", # Karnataka (inter-state)
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 25, # 250,000 base + 18% IGST (45,000) = 295,000 total
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "85238020",
                    "gst_rate": 18.0
                }
            ]
        }
        inv3 = self.client.post("/api/v1/invoices", json=inv3_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/invoices/{inv3['id']}/finalize", headers=self.headers_a)

        # 4. Post and finalize a Credit Note linked to inv1
        cn_payload = {
            "invoice_id": inv1["id"],
            "issue_date": str(date.today()),
            "reason": "Discount post-billing",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 1000.00,
                    "hsn_sac": "85238020",
                    "gst_rate": 18.0
                }
            ]
        }
        cn = self.client.post("/api/v1/invoices/credit-notes", json=cn_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/invoices/credit-notes/{cn['id']}/finalize", headers=self.headers_a)

        # 5. Fetch GSTR-1 report
        res_gstr1 = self.client.get("/api/v1/gst/gstr1", headers=self.headers_a)
        self.assertEqual(res_gstr1.status_code, 200)
        g1 = res_gstr1.json()

        # Assert B2B section contains 1 invoice
        self.assertEqual(len(g1["b2b"]), 1)
        self.assertEqual(g1["b2b"][0]["customer_gstin"], "27AAACT1234A1Z1")
        self.assertEqual(float(g1["b2b"][0]["taxable_value"]), 10000.00)
        self.assertEqual(float(g1["b2b"][0]["cgst_amount"]), 900.00)

        # Assert B2CL section contains 1 large invoice
        self.assertEqual(len(g1["b2cl"]), 1)
        self.assertEqual(g1["b2cl"][0]["pos_state_code"], "29")
        self.assertEqual(float(g1["b2cl"][0]["taxable_value"]), 250000.00)
        self.assertEqual(float(g1["b2cl"][0]["igst_amount"]), 45000.00)

        # Assert B2CS section contains 1 summarized line
        self.assertEqual(len(g1["b2cs"]), 1)
        self.assertEqual(g1["b2cs"][0]["pos_state_code"], "27")
        self.assertEqual(float(g1["b2cs"][0]["taxable_value"]), 10000.00)

        # Assert CDNR section contains 1 credit note
        self.assertEqual(len(g1["cdnr"]), 1)
        self.assertEqual(g1["cdnr"][0]["note_type"], "CREDIT")
        self.assertEqual(g1["cdnr"][0]["customer_gstin"], "27AAACT1234A1Z1")
        self.assertEqual(float(g1["cdnr"][0]["taxable_value"]), 1000.00)

        # Assert HSN summary contains 1 line
        self.assertEqual(len(g1["hsn_summary"]), 1)
        self.assertEqual(g1["hsn_summary"][0]["hsn_sac"], "85238020")
        self.assertEqual(float(g1["hsn_summary"][0]["total_quantity"]), 27.00) # 1 (inv1) + 1 (inv2) + 25 (inv3)
        self.assertEqual(float(g1["hsn_summary"][0]["taxable_value"]), 270000.00)

    def test_gstr2_returns_compilation(self):
        # 1. Post and finalize vendor bill: (subtotal = 5000, CGST = 450, SGST = 450)
        bill_payload = {
            "contact_id": str(self.vendor_b2b_id),
            "bill_number": "BILL-TAX-555",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29", # Karnataka
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 5000.00,
                    "discount": 0.00,
                    "hsn_sac": "85238020",
                    "gst_rate": 18.0
                }
            ]
        }
        bill = self.client.post("/api/v1/bills", json=bill_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/bills/{bill['id']}/finalize", headers=self.headers_a)

        # 2. Fetch GSTR-2 report
        res_gstr2 = self.client.get("/api/v1/gst/gstr2", headers=self.headers_a)
        self.assertEqual(res_gstr2.status_code, 200)
        g2 = res_gstr2.json()

        # Assert B2B purchases contains 1 entry
        self.assertEqual(len(g2["b2b_purchases"]), 1)
        self.assertEqual(g2["b2b_purchases"][0]["vendor_gstin"], "29AAACI5678B2Z2")
        self.assertEqual(float(g2["b2b_purchases"][0]["taxable_value"]), 5000.00)
        self.assertEqual(float(g2["b2b_purchases"][0]["cgst_amount"]), 450.00)

    def test_tenant_boundary_isolation(self):
        # Fetch reports from Tenant B context (which is empty)
        res_g1 = self.client.get("/api/v1/gst/gstr1", headers=self.headers_b).json()
        self.assertEqual(len(res_g1["b2b"]), 0)
        self.assertEqual(len(res_g1["b2cs"]), 0)

        res_g2 = self.client.get("/api/v1/gst/gstr2", headers=self.headers_b).json()
        self.assertEqual(len(res_g2["b2b_purchases"]), 0)

if __name__ == "__main__":
    unittest.main()
