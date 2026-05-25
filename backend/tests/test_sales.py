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
from src.core.database import SessionLocal, tenant_context
from src.infrastructure.database.models import Invoice, Contact, Product

class TestSalesAnalytics(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.tenant_id = uuid.UUID("0aa85f64-5717-4562-b3fc-2c963f66b110")
        self.headers = {"X-Tenant-ID": str(self.tenant_id)}

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
