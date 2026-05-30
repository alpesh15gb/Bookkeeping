import sys
import os
import uuid
from datetime import date
from decimal import Decimal
import unittest
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import SessionLocal, tenant_context, Base, engine
from src.infrastructure.database.models import Invoice, Contact, Product, User, Tenant, TenantMembership

class TestSalesAnalytics(unittest.TestCase):
    def setUp(self):
        # Reset database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # Register a tenant
        reg_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma",
            "phone_number": "+919999988888",
            "company_legal_name": "Varma Ventures Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z6",
            "company_pan": "BBBBB2222B"
        }
        self.client.post("/api/v1/auth/register", json=reg_payload)
        login_res = self.client.post("/api/v1/auth/login", json={
            "email": "owner@company.com",
            "password": "SecurePassword123!"
        }).json()
        self.access_token = login_res["access_token"]

        # Fetch tenant ID
        db = SessionLocal()
        try:
            membership = db.query(TenantMembership).first()
            self.tenant_id = membership.tenant_id
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.access_token}"
        }

    def test_sales_summary_calculations(self):
        # Fetch initial dashboard summary
        res = self.client.get("/api/v1/sales/summary", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        
        # Verify keys are present
        self.assertIn("total_sales", data)
        self.assertIn("total_received", data)
        self.assertIn("outstanding", data)
        self.assertIn("total_gst_liability", data)

    def test_customer_wise_sales(self):
        res = self.client.get("/api/v1/sales/customer-wise", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertIsInstance(res.json(), list)

    def test_period_wise_sales(self):
        res = self.client.get("/api/v1/sales/period-wise", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertIsInstance(res.json(), list)

if __name__ == "__main__":
    unittest.main()
