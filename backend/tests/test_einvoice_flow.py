import sys
import os
import uuid
import unittest
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from unittest.mock import patch
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product, Invoice, TenantSetting, BankingProfile
)

class TestEInvoiceFlow(unittest.TestCase):
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

        # Retrieve Tenant A details
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

            # Seed B2B Customer (Registered)
            self.customer_b2b = Contact(
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

            # Seed B2C Customer (Unregistered)
            self.customer_b2c = Contact(
                id=uuid.UUID("22222222-2222-2222-2222-22222222222b"),
                tenant_id=self.tenant_a_id,
                name="Individual Consumer",
                contact_type="CUSTOMER",
                gstin=None,
                pan=None,
                registration_type="CONSUMER",
                billing_address={"street": "2, Consumer Rd", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True
            )

            # Seed Product
            self.product = Product(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333c"),
                tenant_id=self.tenant_a_id,
                name="Consulting Services",
                sku="SRV-CONS",
                hsn_sac="998311",
                product_type="SERVICE",
                uom="HRS",
                sales_price=Decimal("5000.00"),
                purchase_price=Decimal("0.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )

            db.add_all([bank_a, self.customer_b2b, self.customer_b2c, self.product])
            db.commit()

            self.customer_b2b_id = self.customer_b2b.id
            self.customer_b2c_id = self.customer_b2c.id
            self.product_id = self.product.id
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

    def test_e_invoice_lifecycle_and_rules(self):
        # 1. Post a B2B sales invoice (Draft)
        inv_payload = {
            "contact_id": str(self.customer_b2b_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 10,
                    "rate": 5000.00,
                    "discount": 0.00,
                    "hsn_sac": "998311",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]

        # 2. Assert generating e-invoice on draft invoice fails
        res_e1 = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)
        self.assertEqual(res_e1.status_code, 400)
        self.assertIn("Please finalize it first", res_e1.json()["detail"])

        # 3. Finalize the invoice
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        # 4. Assert generating e-invoice fails if e-invoicing is disabled
        res_e2 = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)
        self.assertEqual(res_e2.status_code, 400)
        self.assertIn("e-Invoicing is not enabled", res_e2.json()["detail"])

        # 5. Enable e-invoicing in Tenant A settings
        db = SessionLocal()
        try:
            setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == self.tenant_a_id).first()
            if not setting:
                setting = TenantSetting(tenant_id=self.tenant_a_id)
                db.add(setting)
            setting.e_invoicing_enabled = True
            db.commit()
        finally:
            db.close()

        # 6. Post and finalize a B2C sales invoice to test B2B-only constraint
        b2c_payload = {
            "contact_id": str(self.customer_b2c_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 1000.00,
                    "discount": 0.00,
                    "hsn_sac": "998311",
                    "gst_rate": 18.0
                }
            ]
        }
        b2c_inv = self.client.post("/api/v1/invoices", json=b2c_payload, headers=self.headers_a).json()
        b2c_id = b2c_inv["id"]
        self.client.post(f"/api/v1/invoices/{b2c_id}/finalize", headers=self.headers_a)

        res_e3 = self.client.post(f"/api/v1/invoices/{b2c_id}/e-invoice", headers=self.headers_a)
        self.assertEqual(res_e3.status_code, 400)
        self.assertIn("B2B transactions", res_e3.json()["detail"])

        # 7. Generate e-invoice for B2B invoice (Should succeed)
        res_e4 = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)
        self.assertEqual(res_e4.status_code, 200)
        e_data = res_e4.json()
        self.assertEqual(e_data["invoice_id"], invoice_id)
        self.assertEqual(e_data["e_invoice_status"], "GENERATED")
        self.assertTrue(len(e_data["irn"]) == 64)
        self.assertTrue(len(e_data["qr_code"]) > 0)

        # 8. Assert duplicate generation fails
        res_e5 = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)
        self.assertEqual(res_e5.status_code, 400)
        self.assertIn("already generated", res_e5.json()["detail"])

        # 9. Cancel e-invoice (Should succeed)
        cancel_payload = {
            "cancel_reason": "2",  # Data entry mistake
            "cancel_remarks": "Test Cancellation"
        }
        res_e6 = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice/cancel", json=cancel_payload, headers=self.headers_a)
        self.assertEqual(res_e6.status_code, 200)
        c_data = res_e6.json()
        self.assertEqual(c_data["invoice_id"], invoice_id)
        self.assertEqual(c_data["e_invoice_status"], "CANCELLED")

        # 10. Assert cancelling already cancelled fails
        res_e7 = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice/cancel", json=cancel_payload, headers=self.headers_a)
        self.assertEqual(res_e7.status_code, 400)
        self.assertIn("Status is not GENERATED", res_e7.json()["detail"])

    def test_24_hour_cancellation_constraint(self):
        # 1. Enable e-invoicing
        db = SessionLocal()
        try:
            setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == self.tenant_a_id).first()
            if not setting:
                setting = TenantSetting(tenant_id=self.tenant_a_id)
                db.add(setting)
            setting.e_invoicing_enabled = True
            db.commit()
        finally:
            db.close()

        # 2. Post and finalize a B2B invoice
        inv_payload = {
            "contact_id": str(self.customer_b2b_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 10,
                    "rate": 5000.00,
                    "discount": 0.00,
                    "hsn_sac": "998311",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        # 3. Generate e-invoice
        self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)

        # 4. Mock updated_at to be 25 hours ago
        db = SessionLocal()
        try:
            invoice = db.query(Invoice).filter(Invoice.id == uuid.UUID(invoice_id)).first()
            invoice.updated_at = datetime.utcnow() - timedelta(hours=25)
            db.commit()
        finally:
            db.close()

        # 5. Assert cancellation fails with 24 hour limit error
        cancel_payload = {
            "cancel_reason": "3",  # Order cancelled
            "cancel_remarks": "Late cancellation"
        }
        res_cancel = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice/cancel", json=cancel_payload, headers=self.headers_a)
        self.assertEqual(res_cancel.status_code, 400)
        self.assertIn("Cancellation not allowed after 24 hours", res_cancel.json()["detail"])

    def test_irp_failure_marks_invoice_failed_without_local_irn(self):
        db = SessionLocal()
        try:
            setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == self.tenant_a_id).first()
            if not setting:
                setting = TenantSetting(tenant_id=self.tenant_a_id)
                db.add(setting)
            setting.e_invoicing_enabled = True
            db.commit()
        finally:
            db.close()

        inv_payload = {
            "contact_id": str(self.customer_b2b_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 5000.00,
                    "discount": 0.00,
                    "hsn_sac": "998311",
                    "gst_rate": 18.0,
                }
            ],
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        with patch(
            "src.domains.taxation.einvoice_service.EInvoiceService._call_irp_generate_invoice",
            side_effect=RuntimeError("IRP unavailable"),
        ):
            res = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)

        self.assertEqual(res.status_code, 502)
        self.assertIn("IRP e-invoice generation failed", res.json()["detail"])

        db = SessionLocal()
        try:
            failed_invoice = db.query(Invoice).filter(Invoice.id == uuid.UUID(invoice_id)).first()
            self.assertEqual(failed_invoice.e_invoice_status, "FAILED")
            self.assertIsNone(failed_invoice.irn)
            self.assertIsNone(failed_invoice.qr_code)
            self.assertIn("IRP unavailable", failed_invoice.e_invoice_error)
        finally:
            db.close()

    def test_tenant_boundary_isolation(self):
        # 1. Enable e-invoicing for Tenant A
        db = SessionLocal()
        try:
            setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == self.tenant_a_id).first()
            if not setting:
                setting = TenantSetting(tenant_id=self.tenant_a_id)
                db.add(setting)
            setting.e_invoicing_enabled = True
            db.commit()
        finally:
            db.close()

        # 2. Post and finalize a B2B invoice under Tenant A
        inv_payload = {
            "contact_id": str(self.customer_b2b_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 10,
                    "rate": 5000.00,
                    "discount": 0.00,
                    "hsn_sac": "998311",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        invoice_id = inv["id"]
        self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a)

        # 3. Assert Tenant B cannot generate e-invoice for Tenant A's invoice (returns 404/403 context boundary check)
        res_gen = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_b)
        self.assertEqual(res_gen.status_code, 404)

        # Generate e-invoice under Tenant A
        self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a)

        # 4. Assert Tenant B cannot cancel Tenant A's e-invoice
        cancel_payload = {
            "cancel_reason": "1",
            "cancel_remarks": "Steal cancel"
        }
        res_cancel = self.client.post(f"/api/v1/invoices/{invoice_id}/e-invoice/cancel", json=cancel_payload, headers=self.headers_b)
        self.assertEqual(res_cancel.status_code, 404)

if __name__ == "__main__":
    unittest.main()
