import os
import sys
import uuid
import unittest
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import Contact, Product, Tenant, TenantMembership, User


class TestVendorBills(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        reg_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma",
            "phone_number": "+919999988888",
            "company_legal_name": "Varma Ventures Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z6",
            "company_pan": "BBBBB2222B",
        }
        self.client.post("/api/v1/auth/register", json=reg_payload)
        res_login = self.client.post(
            "/api/v1/auth/login",
            json={"email": "owner@company.com", "password": "SecurePassword123!"},
        )
        self.access_token = res_login.json()["access_token"]

        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == "owner@company.com").first()
            membership = db.query(TenantMembership).filter(
                TenantMembership.user_id == user.id
            ).first()
            self.tenant_id = membership.tenant_id
            tenant = db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
            tenant.tax_mode = "GST_REGULAR"

            db.add(Contact(
                id=uuid.UUID("3fa85f64-5717-4562-b3fc-2c963f66afa7"),
                tenant_id=self.tenant_id,
                name="Infosys Technologies Ltd",
                email="accounts@infosys.com",
                phone="+918028520261",
                contact_type="BOTH",
                gstin="29AAACI5678B2Z2",
                pan="AAACI5678B",
                registration_type="REGULAR",
                billing_address={
                    "street": "Electronics City, Hosur Road",
                    "city": "Bengaluru",
                    "state": "Karnataka",
                    "state_code": "29",
                    "pincode": "560100",
                    "country": "India",
                },
                state_code="29",
                is_active=True,
            ))
            db.add(Product(
                id=uuid.UUID("4fa85f64-5717-4562-b3fc-2c963f66afd9"),
                tenant_id=self.tenant_id,
                name="MacBook Pro M3 Max",
                sku="APL-MBP-M3MX",
                hsn_sac="84713010",
                product_type="GOODS",
                current_stock=Decimal("1000.00"),
                opening_stock=Decimal("1000.00"),
                uom="PCS",
                sales_price=Decimal("249900.00"),
                purchase_price=Decimal("200000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True,
            ))
            db.commit()
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.access_token}",
        }

    def test_save_posts_bill_and_payment_uses_central_api(self):
        payload = {
            "contact_id": "3fa85f64-5717-4562-b3fc-2c963f66afa7",
            # bill_number intentionally omitted: backend owns numbering
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29",
            "line_items": [{
                "product_id": "4fa85f64-5717-4562-b3fc-2c963f66afd9",
                "quantity": 1,
                "rate": 200000.00,
                "discount": 0.00,
                "hsn_sac": "84713010",
                "gst_rate": 18.0,
            }],
        }
        res = self.client.post("/api/v1/bills", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 201, res.text)
        data = res.json()
        self.assertEqual(data["status"], "POSTED")
        self.assertTrue(data["bill_number"])
        self.assertEqual(float(data["total"]), 236000.00)
        bill_id = data["id"]

        pay_payload = {
            "contact_id": "3fa85f64-5717-4562-b3fc-2c963f66afa7",
            "payment_number": "VPAY-TEST-001",
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 236000.00,
            "allocations": [{"bill_id": bill_id, "amount": 236000.00}],
        }
        payment = self.client.post(
            "/api/v1/payments/disbursements", json=pay_payload, headers=self.headers
        )
        self.assertEqual(payment.status_code, 201, payment.text)
        self.assertEqual(payment.json()["status"], "ACTIVE")

        bill = self.client.get(f"/api/v1/bills/{bill_id}", headers=self.headers)
        self.assertEqual(bill.status_code, 200, bill.text)
        self.assertEqual(bill.json()["status"], "PAID")
        self.assertEqual(float(bill.json()["amount_paid"]), 236000.00)

    def test_preview_bill_returns_200_with_full_totals(self):
        """Regression: preview must serialize a full BillResponse (itc_eligible etc.),
        not blow up into a 500 ResponseValidationError."""
        payload = {
            "contact_id": "3fa85f64-5717-4562-b3fc-2c963f66afa7",
            "bill_number": "PREVIEW-TEST-001",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29",
            "line_items": [{
                "product_id": "4fa85f64-5717-4562-b3fc-2c963f66afd9",
                "quantity": 1,
                "rate": 200000.00,
                "discount": 0.00,
                "hsn_sac": "84713010",
                "gst_rate": 18.0,
            }],
            "discount_rate": 0.0,
            "shipping_charges": 0.0,
            "tds_rate": 0.0,
            "is_gst_inclusive": False,
            "itc_eligible": True,
            "post_on_create": False,
        }
        res = self.client.post("/api/v1/bills/preview", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["status"], "DRAFT")
        self.assertEqual(data["bill_number"], "PREVIEW")
        self.assertTrue(data["itc_eligible"])
        self.assertEqual(float(data["subtotal"]), 200000.00)
        self.assertEqual(float(data["cgst_amount"]), 18000.00)
        self.assertEqual(float(data["sgst_amount"]), 18000.00)
        self.assertEqual(float(data["total"]), 236000.00)


if __name__ == "__main__":
    unittest.main()
