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
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import Contact, Product, TenantMembership

class TestVendorBills(unittest.TestCase):
    def setUp(self):
        # 1. Reset test database tables to force seeds refresh
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # Register/Login a user to get authorization
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
        login_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!"
        }
        res_login = self.client.post("/api/v1/auth/login", json=login_payload)
        token_data = res_login.json()
        self.access_token = token_data["access_token"]

        # Fetch the generated tenant ID
        db = SessionLocal()
        try:
            membership = db.query(TenantMembership).first()
            self.tenant_id = membership.tenant_id

            # 2. Seed fresh context details under correct tenant_id
            vendor = Contact(
                id=uuid.UUID("3fa85f64-5717-4562-b3fc-2c963f66afa7"),
                tenant_id=self.tenant_id,
                name="Infosys Technologies Ltd",
                email="accounts@infosys.com",
                phone="+918028520261",
                contact_type="BOTH",
                gstin="29AAACI5678B2Z2",
                pan="AAACI5678B",
                registration_type="REGULAR",
                billing_address={"street": "Electronics City, Hosur Road", "city": "Bengaluru", "state": "Karnataka", "state_code": "29", "pincode": "560100", "country": "India"},
                state_code="29",
                is_active=True
            )
            product = Product(
                id=uuid.UUID("4fa85f64-5717-4562-b3fc-2c963f66afd9"),
                tenant_id=self.tenant_id,
                name="MacBook Pro M3 Max",
                sku="APL-MBP-M3MX",
                hsn_sac="84713010",
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("249900.00"),
                purchase_price=Decimal("200000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )
            db.add_all([vendor, product])
            db.commit()
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.access_token}"
        }

    def test_create_and_finalize_vendor_bill(self):
        # Create a draft bill
        payload = {
            "contact_id": "3fa85f64-5717-4562-b3fc-2c963f66afa7",
            "bill_number": "BILL-TEST-009",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29", # Karnataka (IGST)
            "line_items": [
                {
                    "product_id": "4fa85f64-5717-4562-b3fc-2c963f66afd9",
                    "quantity": 1,
                    "rate": 200000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        res = self.client.post("/api/v1/bills", json=payload, headers=self.headers)
        
        # Debug print in case it fails
        if res.status_code != 201:
            print("FAILED RESPONSE BODY:", res.text)
            
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["status"], "DRAFT")
        self.assertEqual(float(data["total"]), 236000.00) # 200000 + 18% IGST (36000)
        bill_id = data["id"]

        # Finalize draft bill
        res_fin = self.client.post(f"/api/v1/bills/{bill_id}/finalize", headers=self.headers)
        self.assertEqual(res_fin.status_code, 200)
        data_fin = res_fin.json()
        self.assertEqual(data_fin["status"], "POSTED")

        # Record payment out
        pay_payload = {
            "contact_id": "3fa85f64-5717-4562-b3fc-2c963f66afa7",
            "payment_number": "VPAY-TEST-001",
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 236000.00,
            "allocations": [
                {
                    "bill_id": bill_id,
                    "amount": 236000.00
                }
            ]
        }
        res_pay = self.client.post(f"/api/v1/bills/{bill_id}/payment", json=pay_payload, headers=self.headers)
        self.assertEqual(res_pay.status_code, 200)
        data_pay = res_pay.json()
        self.assertEqual(data_pay["status"], "PAID")
        self.assertEqual(float(data_pay["amount_paid"]), 236000.00)

if __name__ == "__main__":
    unittest.main()
