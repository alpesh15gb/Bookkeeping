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
from src.core.security import ROLE_PERMISSIONS, create_access_token, get_password_hash
from src.infrastructure.database.models import Contact, Product, Tenant, TenantMembership, User


class TestDashboard(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)
        db = SessionLocal()
        try:
            self.user_id = uuid.uuid4()
            self.tenant_a_id = uuid.uuid4()
            db.add(User(
                id=self.user_id,
                email="dashboard_a@company.com",
                password_hash=get_password_hash("SecurePassword123!"),
                full_name="Dashboard A",
                phone_number="+919876543210",
                is_active=True,
                email_verified=True,
            ))
            db.add(Tenant(
                id=self.tenant_a_id,
                legal_name="Dashboard Corp A",
                trade_name="Dashboard A",
                gstin="27AAPFU0939F1ZV",
                tax_mode="GST_REGULAR",
                pan="AAPFU0939F",
                financial_year_start=date(2026, 4, 1),
            ))
            db.add(TenantMembership(
                user_id=self.user_id,
                tenant_id=self.tenant_a_id,
                role="OWNER",
                is_active=True,
            ))
            contact = Contact(
                id=uuid.uuid4(), tenant_id=self.tenant_a_id, name="Customer A",
                email="cust_a@test.com", phone="+919876543210",
                contact_type="CUSTOMER", gstin="27AAACT1234A1Z1",
                pan="AAACTC1234A", registration_type="REGULAR",
                billing_address={"street": "123 Main St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27", is_active=True,
            )
            product = Product(
                id=uuid.uuid4(), tenant_id=self.tenant_a_id, name="Product A",
                sku="PA-001", hsn_sac="84713010", product_type="GOODS",
                current_stock=Decimal("1000"), opening_stock=Decimal("1000"),
                uom="PCS", sales_price=Decimal("10000"),
                purchase_price=Decimal("8000"), gst_rate=Decimal("18"),
                is_active=True,
            )
            db.add_all([contact, product])
            db.commit()
            self.contact_id = str(contact.id)
            self.product_id = str(product.id)
        finally:
            db.close()
        token = create_access_token(
            user_id=str(self.user_id), scopes=ROLE_PERMISSIONS.get("owner", [])
        )
        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a_id),
            "Authorization": f"Bearer {token}",
        }

    def _create_posted_invoice(self, amount=10000.0):
        response = self.client.post("/api/v1/invoices", json={
            "contact_id": self.contact_id,
            "invoice_number": f"INV-DASH-{uuid.uuid4().hex[:6].upper()}",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": self.product_id, "quantity": 1, "rate": amount,
                "discount": 0, "hsn_sac": "84713010", "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()["id"]

    def test_metrics_returns_totals(self):
        self._create_posted_invoice()
        data = self.client.get("/api/v1/dashboard/metrics", headers=self.headers_a).json()
        self.assertEqual(data["cgst_total"], 900.0)
        self.assertEqual(data["sgst_total"], 900.0)
        self.assertEqual(data["igst_total"], 0.0)
        self.assertIn("cess_total", data)

    def test_metrics_accumulates_multiple_invoices(self):
        self._create_posted_invoice(10000)
        self._create_posted_invoice(20000)
        response = self.client.get("/api/v1/dashboard/metrics", headers=self.headers_a)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertAlmostEqual(data["cgst_total"], 2700.0, places=2)
        self.assertAlmostEqual(data["sgst_total"], 2700.0, places=2)

    def test_revenue_and_expense_trends_empty(self):
        revenue = self.client.get("/api/v1/dashboard/revenue-trend", headers=self.headers_a)
        expense = self.client.get("/api/v1/dashboard/expense-trend", headers=self.headers_a)
        self.assertEqual(revenue.status_code, 200)
        self.assertEqual(expense.status_code, 200)
        self.assertEqual(revenue.json(), [])
        self.assertEqual(expense.json(), [])

    def test_every_saved_invoice_is_in_metrics(self):
        # There is no public Draft mode anymore; Save posts the invoice.
        self._create_posted_invoice(100000)
        data = self.client.get("/api/v1/dashboard/metrics", headers=self.headers_a).json()
        self.assertEqual(data["cgst_total"], 9000.0)
        self.assertEqual(data["sgst_total"], 9000.0)

    def test_revenue_trend_with_data(self):
        self._create_posted_invoice(10000)
        response = self.client.get("/api/v1/dashboard/revenue-trend", headers=self.headers_a)
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertGreater(len(data), 0)
        for field in ("month", "year", "total"):
            self.assertIn(field, data[0])

    def test_tenant_isolation(self):
        self._create_posted_invoice(10000)
        db = SessionLocal()
        try:
            user_b_id = uuid.uuid4()
            tenant_b_id = uuid.uuid4()
            db.add(User(
                id=user_b_id,
                email="dashboard_b@company.com",
                password_hash=get_password_hash("SecurePassword123!"),
                full_name="Dashboard B",
                phone_number="+919876543211",
                is_active=True,
                email_verified=True,
            ))
            db.add(Tenant(
                id=tenant_b_id,
                legal_name="Dashboard Corp B",
                trade_name="Dashboard B",
                gstin="29BBBBB2222B2Z6",
                pan="BBBBB2222B",
                financial_year_start=date(2026, 4, 1),
            ))
            db.add(TenantMembership(
                user_id=user_b_id, tenant_id=tenant_b_id, role="OWNER", is_active=True
            ))
            db.commit()
        finally:
            db.close()
        token_b = create_access_token(
            user_id=str(user_b_id), scopes=ROLE_PERMISSIONS.get("owner", [])
        )
        headers_b = {
            "X-Tenant-ID": str(tenant_b_id),
            "Authorization": f"Bearer {token_b}",
        }
        data_b = self.client.get("/api/v1/dashboard/metrics", headers=headers_b).json()
        self.assertEqual(data_b["cgst_total"], 0.0)
        self.assertEqual(data_b["sgst_total"], 0.0)
        data_a = self.client.get("/api/v1/dashboard/metrics", headers=self.headers_a).json()
        self.assertEqual(data_a["cgst_total"], 900.0)

    def test_metrics_requires_auth(self):
        response = self.client.get(
            "/api/v1/dashboard/metrics",
            headers={"X-Tenant-ID": str(self.tenant_a_id)},
        )
        self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
