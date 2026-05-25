import sys
import os
import uuid
import unittest
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product, Invoice, EWayBill, BankingProfile
)

class TestEWayBillFlow(unittest.TestCase):
    def setUp(self):
        # Reset test database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # 1. Register and login Tenant A
        reg_payload_a = {
            "email": "owner_a@company.com",
            "password": "SecurePassword123!",
            "full_name": "Tenant A Owner",
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

        # 2. Register and login Tenant B
        reg_payload_b = {
            "email": "owner_b@company.com",
            "password": "SecurePassword123!",
            "full_name": "Tenant B Owner",
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

        # Retrieve Tenant A & B details
        db = SessionLocal()
        try:
            m_a = db.query(TenantMembership).filter(
                TenantMembership.user_id == db.query(User).filter(User.email == "owner_a@company.com").first().id
            ).first()
            self.tenant_a_id = m_a.tenant_id

            m_b = db.query(TenantMembership).filter(
                TenantMembership.user_id == db.query(User).filter(User.email == "owner_b@company.com").first().id
            ).first()
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

            # Seed Customer
            self.customer = Contact(
                id=uuid.UUID("11111111-1111-1111-1111-11111111111a"),
                tenant_id=self.tenant_a_id,
                name="B2B Corporation",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={"street": "1, GSTR St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True
            )

            # Seed Goods Product
            self.product_goods = Product(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333c"),
                tenant_id=self.tenant_a_id,
                name="Ergonomic Chairs",
                sku="FUR-CH-ERGO",
                hsn_sac="94031000",
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("12000.00"),
                purchase_price=Decimal("8000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )

            # Seed Service Product
            self.product_service = Product(
                id=uuid.UUID("44444444-4444-4444-4444-44444444444d"),
                tenant_id=self.tenant_a_id,
                name="Chair Installation Services",
                sku="SRV-INSTALL",
                hsn_sac="998713",
                product_type="SERVICE",
                uom="HRS",
                sales_price=Decimal("2000.00"),
                purchase_price=Decimal("0.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )

            db.add_all([bank_a, self.customer, self.product_goods, self.product_service])
            db.commit()

            self.customer_id = self.customer.id
            self.product_goods_id = self.product_goods.id
            self.product_service_id = self.product_service.id
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

    def test_eway_bill_lifecycle_and_validations(self):
        # 1. Post a sales invoice with both goods and services (Draft)
        inv_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_goods_id),
                    "quantity": 5,
                    "rate": 12000.00,
                    "discount": 0.00,
                    "hsn_sac": "94031000",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]

        # 2. Test that e-way bill generation fails on a draft invoice
        ewb_payload = {
            "invoice_id": invoice_id,
            "trans_distance": 150,
            "vehicle_number": "MH12PQ1234",
            "transporter_id": "27AAACT1234A1Z1"
        }
        res_e1 = self.client.post("/api/v1/eway-bills", json=ewb_payload, headers=self.headers_a)
        self.assertEqual(res_e1.status_code, 400)
        self.assertIn("Please finalize it first", res_e1.json()["detail"])

        # 3. Finalize the invoice
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        # 4. Generate e-way bill successfully
        res_e2 = self.client.post("/api/v1/eway-bills", json=ewb_payload, headers=self.headers_a)
        self.assertEqual(res_e2.status_code, 201)
        ewb_data = res_e2.json()
        self.assertEqual(ewb_data["invoice_id"], invoice_id)
        self.assertEqual(ewb_data["status"], "GENERATED")
        self.assertTrue(ewb_data["eway_bill_number"].startswith("201"))
        self.assertEqual(ewb_data["trans_distance"], 150)
        
        # Verify valid_until calculation (distance 150km -> 1 day validity)
        valid_until_dt = datetime.fromisoformat(ewb_data["valid_until"])
        created_at_dt = datetime.fromisoformat(ewb_data["created_at"])
        validity_delta = valid_until_dt - created_at_dt
        self.assertAlmostEqual(validity_delta.total_seconds(), 24 * 3600, delta=60) # 1 day validity

        ewb_id = ewb_data["id"]

        # 5. List e-way bills and verify listing contains it
        res_list = self.client.get("/api/v1/eway-bills", headers=self.headers_a)
        self.assertEqual(res_list.status_code, 200)
        self.assertEqual(len(res_list.json()), 1)
        self.assertEqual(res_list.json()[0]["id"], ewb_id)

        # 6. Test vehicle update/transhipment details
        update_vehicle_payload = {
            "vehicle_number": "KA03MM9876",
            "vehicle_type": "REGULAR",
            "from_place": "Pune",
            "from_state_code": "27",
            "reason_code": "2",  # Breakdown
            "reason_remarks": "Engine oil leak"
        }
        res_update = self.client.post(f"/api/v1/eway-bills/{ewb_id}/vehicle", json=update_vehicle_payload, headers=self.headers_a)
        self.assertEqual(res_update.status_code, 200)
        updated_data = res_update.json()
        self.assertEqual(updated_data["vehicle_number"], "KA03MM9876")
        self.assertEqual(len(updated_data["vehicle_history"]), 1)
        self.assertEqual(updated_data["vehicle_history"][0]["vehicle_number"], "MH12PQ1234")
        self.assertEqual(updated_data["vehicle_history"][0]["reason_code"], "2")

        # 7. Test cancelling e-way bill within 24h (Should succeed)
        cancel_payload = {
            "cancel_reason": "1",  # Duplicate
            "cancel_remarks": "Double entry"
        }
        res_cancel = self.client.post(f"/api/v1/eway-bills/{ewb_id}/cancel", json=cancel_payload, headers=self.headers_a)
        self.assertEqual(res_cancel.status_code, 200)
        cancelled_data = res_cancel.json()
        self.assertEqual(cancelled_data["status"], "CANCELLED")

        # 8. Assert cancelling already cancelled e-way bill fails
        res_cancel_again = self.client.post(f"/api/v1/eway-bills/{ewb_id}/cancel", json=cancel_payload, headers=self.headers_a)
        self.assertEqual(res_cancel_again.status_code, 400)
        self.assertIn("already cancelled", res_cancel_again.json()["detail"])

    def test_service_only_invoice_fails(self):
        # Post and finalize an invoice containing only service line items
        service_inv_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_service_id),
                    "quantity": 5,
                    "rate": 2000.00,
                    "discount": 0.00,
                    "hsn_sac": "998713",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=service_inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        # Attempting to generate e-way bill should fail
        ewb_payload = {
            "invoice_id": invoice_id,
            "trans_distance": 150,
            "vehicle_number": "MH12PQ1234",
            "transporter_id": "27AAACT1234A1Z1"
        }
        res_ewb = self.client.post("/api/v1/eway-bills", json=ewb_payload, headers=self.headers_a)
        self.assertEqual(res_ewb.status_code, 400)
        self.assertIn("only applicable for movement of GOODS", res_ewb.json()["detail"])

    def test_24_hour_cancellation_constraint(self):
        # 1. Post, finalize, and generate e-way bill
        inv_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_goods_id),
                    "quantity": 10,
                    "rate": 12000.00,
                    "discount": 0.00,
                    "hsn_sac": "94031000",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        ewb_payload = {
            "invoice_id": invoice_id,
            "trans_distance": 100,
            "vehicle_number": "MH12PQ1234"
        }
        ewb = self.client.post("/api/v1/eway-bills", json=ewb_payload, headers=self.headers_a).json()
        ewb_id = ewb["id"]

        # 2. Mock creation date to be 25 hours ago
        db = SessionLocal()
        try:
            db_ewb = db.query(EWayBill).filter(EWayBill.id == uuid.UUID(ewb_id)).first()
            db_ewb.created_at = datetime.utcnow() - timedelta(hours=25)
            db.commit()
        finally:
            db.close()

        # 3. Attempt to cancel and verify 400 error
        cancel_payload = {
            "cancel_reason": "2",
            "cancel_remarks": "Late cancellation attempt"
        }
        res_cancel = self.client.post(f"/api/v1/eway-bills/{ewb_id}/cancel", json=cancel_payload, headers=self.headers_a)
        self.assertEqual(res_cancel.status_code, 400)
        self.assertIn("Cancellation not allowed after 24 hours", res_cancel.json()["detail"])

    def test_consolidated_eway_bill(self):
        # 1. Post and finalize invoice 1
        inv1_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_goods_id),
                    "quantity": 5,
                    "rate": 12000.00,
                    "discount": 0.00,
                    "hsn_sac": "94031000",
                    "gst_rate": 18.0
                }
            ]
        }
        inv1 = self.client.post("/api/v1/invoices", json=inv1_payload, headers=self.headers_a).json()
        invoice1_id = inv1["id"]
        self.client.post(f"/api/v1/invoices/{invoice1_id}/finalize", headers=self.headers_a)

        # 2. Post and finalize invoice 2
        inv2_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_goods_id),
                    "quantity": 10,
                    "rate": 12000.00,
                    "discount": 0.00,
                    "hsn_sac": "94031000",
                    "gst_rate": 18.0
                }
            ]
        }
        inv2 = self.client.post("/api/v1/invoices", json=inv2_payload, headers=self.headers_a).json()
        invoice2_id = inv2["id"]
        self.client.post(f"/api/v1/invoices/{invoice2_id}/finalize", headers=self.headers_a)

        # 3. Generate two e-way bills
        ewb1 = self.client.post("/api/v1/eway-bills", json={
            "invoice_id": invoice1_id,
            "trans_distance": 100,
            "vehicle_number": "MH12PQ1234"
        }, headers=self.headers_a).json()

        ewb2 = self.client.post("/api/v1/eway-bills", json={
            "invoice_id": invoice2_id,
            "trans_distance": 100,
            "vehicle_number": "MH12PQ1234"
        }, headers=self.headers_a).json()

        # 4. Generate consolidated e-way bill
        con_payload = {
            "vehicle_number": "MH12PQ1234",
            "vehicle_type": "REGULAR",
            "from_place": "Pune",
            "from_state_code": "27",
            "eway_bill_numbers": [ewb1["eway_bill_number"], ewb2["eway_bill_number"]]
        }
        res_con = self.client.post("/api/v1/eway-bills/consolidated", json=con_payload, headers=self.headers_a)
        self.assertEqual(res_con.status_code, 200)
        con_data = res_con.json()
        self.assertTrue(con_data["consolidated_eway_bill_number"].startswith("301"))
        self.assertEqual(con_data["status"], "GENERATED")
        self.assertEqual(len(con_data["eway_bills"]), 2)

    def test_tenant_boundary_isolation(self):
        # 1. Post and finalize Tenant A B2B invoice
        inv_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_goods_id),
                    "quantity": 5,
                    "rate": 12000.00,
                    "discount": 0.00,
                    "hsn_sac": "94031000",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        # 2. Assert Tenant B cannot generate e-way bill for Tenant A's invoice
        res_e1 = self.client.post("/api/v1/eway-bills", json={
            "invoice_id": invoice_id,
            "trans_distance": 100,
            "vehicle_number": "MH12PQ1234"
        }, headers=self.headers_b)
        self.assertEqual(res_e1.status_code, 404)

        # Generate e-way bill under Tenant A
        ewb = self.client.post("/api/v1/eway-bills", json={
            "invoice_id": invoice_id,
            "trans_distance": 100,
            "vehicle_number": "MH12PQ1234"
        }, headers=self.headers_a).json()
        ewb_id = ewb["id"]

        # 3. Assert Tenant B cannot retrieve Tenant A's e-way bill
        res_get = self.client.get(f"/api/v1/eway-bills/{ewb_id}", headers=self.headers_b)
        self.assertEqual(res_get.status_code, 404)

        # 4. Assert Tenant B cannot cancel Tenant A's e-way bill
        cancel_payload = {
            "cancel_reason": "1",
            "cancel_remarks": "steal cancel"
        }
        res_cancel = self.client.post(f"/api/v1/eway-bills/{ewb_id}/cancel", json=cancel_payload, headers=self.headers_b)
        self.assertEqual(res_cancel.status_code, 404)

if __name__ == "__main__":
    unittest.main()
