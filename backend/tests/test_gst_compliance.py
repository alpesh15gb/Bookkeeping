import os
import sys
import uuid
import unittest
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import Base, SessionLocal, engine
from src.domains.inventory.services import resolve_default_warehouse_id
from src.infrastructure.database.models import (
    BankingProfile,
    Contact,
    Product,
    StockLedger,
    Tenant,
    TenantMembership,
    User,
)


class TestGSTCompliance(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        for suffix, gstin, pan, phone in (
            ("a", "27AAAAA1111A1Z1", "AAAAA1111A", "+919999988881"),
            ("b", "27BBBBB2222B2Z2", "BBBBB2222B", "+919999988882"),
        ):
            self.client.post("/api/v1/auth/register", json={
                "email": f"owner_{suffix}@company.com",
                "password": "SecurePassword123!",
                "full_name": f"Vijay Varma {suffix.upper()}",
                "phone_number": phone,
                "company_legal_name": f"Tenant {suffix.upper()} Pvt Ltd",
                "company_gstin": gstin,
                "company_pan": pan,
            })
        self.token_a = self.client.post("/api/v1/auth/login", json={
            "email": "owner_a@company.com", "password": "SecurePassword123!"
        }).json()["access_token"]
        self.token_b = self.client.post("/api/v1/auth/login", json={
            "email": "owner_b@company.com", "password": "SecurePassword123!"
        }).json()["access_token"]

        db = SessionLocal()
        try:
            user_a = db.query(User).filter(User.email == "owner_a@company.com").one()
            user_b = db.query(User).filter(User.email == "owner_b@company.com").one()
            self.tenant_a_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user_a.id
            ).one().tenant_id
            self.tenant_b_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user_b.id
            ).one().tenant_id
            db.get(Tenant, self.tenant_a_id).tax_mode = "GST_REGULAR"
            db.get(Tenant, self.tenant_b_id).tax_mode = "GST_REGULAR"
            db.add(BankingProfile(
                tenant_id=self.tenant_a_id,
                bank_name="HDFC Bank", account_number="50001002003004",
                ifsc_code="HDFC0000001", account_holder_name="Tenant A Pvt Ltd",
                is_primary=True, is_active=True,
            ))
            b2b = Contact(
                id=uuid.UUID("11111111-1111-1111-1111-11111111111a"),
                tenant_id=self.tenant_a_id, name="Registered Corp",
                contact_type="CUSTOMER", gstin="27AAACT1234A1Z1",
                pan="AAACT1234A", registration_type="REGULAR",
                billing_address={"street": "1 GSTR-1 St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27", is_active=True,
            )
            b2c = Contact(
                id=uuid.UUID("22222222-2222-2222-2222-22222222222a"),
                tenant_id=self.tenant_a_id, name="Individual Consumer",
                contact_type="BOTH", registration_type="CONSUMER",
                billing_address={"street": "2 B2CS St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27", is_active=True,
            )
            vendor = Contact(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333b"),
                tenant_id=self.tenant_a_id, name="Supplier Pvt Ltd",
                contact_type="VENDOR", gstin="29AAACI5678B2Z2",
                pan="AAACI5678B", registration_type="REGULAR",
                billing_address={"street": "3 Supplier Rd", "city": "Bengaluru", "state": "Karnataka", "state_code": "29", "pincode": "560100", "country": "India"},
                state_code="29", is_active=True,
            )
            product = Product(
                id=uuid.UUID("44444444-4444-4444-4444-44444444444c"),
                tenant_id=self.tenant_a_id, name="Accounting Software License",
                sku="SRV-ACC-LIC", hsn_sac="85238020", product_type="GOODS",
                current_stock=Decimal("1000"), opening_stock=Decimal("1000"),
                uom="PCS", sales_price=Decimal("10000"),
                purchase_price=Decimal("5000"), gst_rate=Decimal("18"),
                is_active=True,
            )
            db.add_all([b2b, b2c, vendor, product])
            db.flush()
            db.add(StockLedger(
                tenant_id=self.tenant_a_id, product_id=product.id,
                warehouse_id=resolve_default_warehouse_id(db, self.tenant_a_id),
                quantity=Decimal("1000"), balance_quantity=Decimal("1000"),
                reference_type="OPENING", reference_id=product.id,
                rate=product.purchase_price,
            ))
            db.commit()
            self.customer_b2b_id = b2b.id
            self.customer_b2c_id = b2c.id
            self.vendor_b2b_id = vendor.id
            self.product_id = product.id
        finally:
            db.close()

        self.headers_a = {"X-Tenant-ID": str(self.tenant_a_id), "Authorization": f"Bearer {self.token_a}"}
        self.headers_b = {"X-Tenant-ID": str(self.tenant_b_id), "Authorization": f"Bearer {self.token_b}"}

    def _invoice(self, contact_id, *, qty=1, rate=10000, pos="27"):
        response = self.client.post("/api/v1/invoices", json={
            "contact_id": str(contact_id), "issue_date": str(date.today()),
            "due_date": str(date.today()), "pos_state_code": pos,
            "line_items": [{
                "product_id": str(self.product_id), "quantity": qty,
                "rate": rate, "discount": 0, "hsn_sac": "85238020", "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()

    def _bill(self, contact_id, number, *, rate, pos):
        response = self.client.post("/api/v1/bills", json={
            "contact_id": str(contact_id), "bill_number": number,
            "issue_date": str(date.today()), "due_date": str(date.today()),
            "pos_state_code": pos,
            "line_items": [{
                "product_id": str(self.product_id), "quantity": 1,
                "rate": rate, "discount": 0, "hsn_sac": "85238020", "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()

    def test_gstr1_returns_compilation(self):
        inv1 = self._invoice(self.customer_b2b_id, rate=10000)
        self._invoice(self.customer_b2c_id, rate=10000, pos="27")
        self._invoice(self.customer_b2c_id, qty=25, rate=10000, pos="29")
        credit = self.client.post("/api/v1/invoices/credit-notes", json={
            "invoice_id": inv1["id"], "issue_date": str(date.today()),
            "reason": "Discount post-billing",
            "line_items": [{
                "product_id": str(self.product_id), "quantity": 1,
                "rate": 1000, "hsn_sac": "85238020", "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(credit.status_code, 201, credit.text)
        self.assertEqual(credit.json()["status"], "POSTED")

        response = self.client.get("/api/v1/gst/gstr1", headers=self.headers_a)
        self.assertEqual(response.status_code, 200, response.text)
        g1 = response.json()
        self.assertEqual(len(g1["b2b"]), 1)
        self.assertEqual(g1["b2b"][0]["customer_gstin"], "27AAACT1234A1Z1")
        self.assertEqual(float(g1["b2b"][0]["taxable_value"]), 10000)
        self.assertEqual(float(g1["b2b"][0]["cgst_amount"]), 900)
        self.assertEqual(len(g1["b2cl"]), 1)
        self.assertEqual(g1["b2cl"][0]["pos_state_code"], "29")
        self.assertEqual(float(g1["b2cl"][0]["taxable_value"]), 250000)
        self.assertEqual(float(g1["b2cl"][0]["igst_amount"]), 45000)
        self.assertEqual(len(g1["b2cs"]), 1)
        self.assertEqual(float(g1["b2cs"][0]["taxable_value"]), 10000)
        self.assertEqual(len(g1["cdnr"]), 1)
        self.assertEqual(g1["cdnr"][0]["note_type"], "CREDIT")
        self.assertEqual(float(g1["cdnr"][0]["taxable_value"]), 1000)
        self.assertEqual(len(g1["hsn_summary"]), 1)
        self.assertEqual(float(g1["hsn_summary"][0]["total_quantity"]), 27)
        self.assertEqual(float(g1["hsn_summary"][0]["taxable_value"]), 270000)

    def test_gstr2_returns_compilation_and_exports(self):
        self._bill(self.vendor_b2b_id, "BILL-TAX-555", rate=5000, pos="29")
        self._bill(self.customer_b2c_id, "BILL-UNREG-777", rate=2000, pos="27")
        response = self.client.get("/api/v1/gst/gstr2", headers=self.headers_a)
        self.assertEqual(response.status_code, 200, response.text)
        g2 = response.json()
        self.assertEqual(len(g2["b2b_purchases"]), 1)
        self.assertEqual(g2["b2b_purchases"][0]["vendor_gstin"], "29AAACI5678B2Z2")
        self.assertEqual(float(g2["b2b_purchases"][0]["taxable_value"]), 5000)
        self.assertEqual(len(g2["b2bur_purchases"]), 1)
        self.assertEqual(float(g2["b2bur_purchases"][0]["taxable_value"]), 2000)
        excel = self.client.get("/api/v1/gst/gstr2/export", headers=self.headers_a)
        pdf = self.client.get("/api/v1/gst/gstr2/pdf", headers=self.headers_a)
        self.assertEqual(excel.status_code, 200)
        self.assertIn("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", excel.headers["content-type"])
        self.assertEqual(pdf.status_code, 200)
        self.assertIn("application/pdf", pdf.headers["content-type"])

    def test_tenant_boundary_isolation(self):
        g1 = self.client.get("/api/v1/gst/gstr1", headers=self.headers_b).json()
        self.assertEqual(len(g1["b2b"]), 0)
        self.assertEqual(len(g1["b2cs"]), 0)
        g2 = self.client.get("/api/v1/gst/gstr2", headers=self.headers_b).json()
        self.assertEqual(len(g2["b2b_purchases"]), 0)


if __name__ == "__main__":
    unittest.main()
