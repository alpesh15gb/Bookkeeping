import os
import sys
import uuid
import unittest
from datetime import date, datetime, timedelta
from decimal import Decimal
from unittest.mock import patch

from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.config import settings
from src.core.database import Base, SessionLocal, engine
from src.infrastructure.database.models import (
    BankingProfile,
    Contact,
    Invoice,
    Product,
    TenantMembership,
    TenantSetting,
    User,
)


class TestEInvoiceFlow(unittest.TestCase):
    def setUp(self):
        settings.COMPLIANCE_MOCK_ENABLED = True
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        for suffix, gstin, pan, phone in (
            ("a", "27AAAAA1111A1Z1", "AAAAA1111A", "+919999988881"),
            ("b", "27BBBBB2222B2Z2", "BBBBB2222B", "+919999988882"),
        ):
            registered = self.client.post("/api/v1/auth/register", json={
                "email": f"owner_{suffix}@company.com",
                "password": "SecurePassword123!",
                "full_name": f"Tenant {suffix.upper()} Owner",
                "phone_number": phone,
                "company_legal_name": f"Tenant {suffix.upper()} Pvt Ltd",
                "company_gstin": gstin,
                "company_pan": pan,
            })
            self.assertEqual(registered.status_code, 201, registered.text)

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
            db.add(BankingProfile(
                tenant_id=self.tenant_a_id,
                bank_name="HDFC Bank",
                account_number="50001002003004",
                ifsc_code="HDFC0000001",
                account_holder_name="Tenant A Pvt Ltd",
                is_primary=True,
                is_active=True,
            ))
            b2b = Contact(
                id=uuid.UUID("11111111-1111-1111-1111-11111111111a"),
                tenant_id=self.tenant_a_id,
                name="B2B Corporation",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={"street": "1 GSTR St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True,
            )
            b2c = Contact(
                id=uuid.UUID("22222222-2222-2222-2222-22222222222b"),
                tenant_id=self.tenant_a_id,
                name="Individual Consumer",
                contact_type="CUSTOMER",
                registration_type="CONSUMER",
                billing_address={"street": "2 Consumer Rd", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True,
            )
            product = Product(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333c"),
                tenant_id=self.tenant_a_id,
                name="Consulting Services",
                sku="SRV-CONS",
                hsn_sac="998311",
                product_type="SERVICE",
                uom="HRS",
                sales_price=Decimal("5000"),
                purchase_price=Decimal("0"),
                gst_rate=Decimal("18"),
                is_active=True,
            )
            db.add_all([b2b, b2c, product])
            db.commit()
            self.customer_b2b_id = b2b.id
            self.customer_b2c_id = b2c.id
            self.product_id = product.id
        finally:
            db.close()

        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a_id),
            "Authorization": f"Bearer {self.token_a}",
        }
        self.headers_b = {
            "X-Tenant-ID": str(self.tenant_b_id),
            "Authorization": f"Bearer {self.token_b}",
        }

    def tearDown(self):
        settings.COMPLIANCE_MOCK_ENABLED = False

    def _invoice(self, customer_id=None):
        response = self.client.post("/api/v1/invoices", json={
            "contact_id": str(customer_id or self.customer_b2b_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": str(self.product_id),
                "quantity": 10,
                "rate": 5000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()

    def _enable(self):
        db = SessionLocal()
        try:
            setting = db.query(TenantSetting).filter(
                TenantSetting.tenant_id == self.tenant_a_id
            ).first()
            if not setting:
                setting = TenantSetting(tenant_id=self.tenant_a_id)
                db.add(setting)
            setting.e_invoicing_enabled = True
            db.commit()
        finally:
            db.close()

    def test_e_invoice_lifecycle_and_rules(self):
        invoice = self._invoice()
        invoice_id = invoice["id"]
        disabled = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a
        )
        self.assertEqual(disabled.status_code, 400)
        self.assertIn("e-Invoicing is not enabled", disabled.json()["detail"])

        self._enable()
        b2c = self._invoice(self.customer_b2c_id)
        b2c_result = self.client.post(
            f"/api/v1/invoices/{b2c['id']}/e-invoice", headers=self.headers_a
        )
        self.assertEqual(b2c_result.status_code, 400)
        self.assertIn("B2B transactions", b2c_result.json()["detail"])

        generated = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a
        )
        self.assertEqual(generated.status_code, 200, generated.text)
        data = generated.json()
        self.assertEqual(data["e_invoice_status"], "GENERATED")
        self.assertEqual(len(data["irn"]), 64)
        self.assertTrue(data["qr_code"])
        duplicate = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a
        )
        self.assertEqual(duplicate.status_code, 400)

        cancel_payload = {"cancel_reason": "2", "cancel_remarks": "Test Cancellation"}
        cancelled = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice/cancel",
            json=cancel_payload,
            headers=self.headers_a,
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        self.assertEqual(cancelled.json()["e_invoice_status"], "CANCELLED")
        again = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice/cancel",
            json=cancel_payload,
            headers=self.headers_a,
        )
        self.assertEqual(again.status_code, 400)

    def test_production_refuses_mock_irn(self):
        """Regression: mock mode fabricates IRNs; production must fail closed
        instead of persisting a fake IRN on a live invoice."""
        original_env = settings.APP_ENV
        original_base = settings.IRP_BASE_URL
        try:
            settings.APP_ENV = "production"
            settings.IRP_BASE_URL = "https://einvoice1-sandbox.nic.in"
            invoice = self._invoice()
            self._enable()
            resp = self.client.post(
                f"/api/v1/invoices/{invoice['id']}/e-invoice", headers=self.headers_a
            )
            self.assertEqual(resp.status_code, 502, resp.text)
            self.assertIn("forbidden in production", resp.json()["detail"])
            db = SessionLocal()
            try:
                inv = db.query(Invoice).filter(
                    Invoice.id == uuid.UUID(invoice["id"])
                ).first()
                self.assertNotEqual(inv.e_invoice_status, "GENERATED")
                self.assertIsNone(inv.irn)
            finally:
                db.close()
        finally:
            settings.APP_ENV = original_env
            settings.IRP_BASE_URL = original_base

    def test_production_requires_irp_host_and_credentials(self):
        """Regression: with mock off, a missing IRP host must fail closed in
        production instead of reaching for a default sandbox URL."""
        original_env = settings.APP_ENV
        original_mock = settings.COMPLIANCE_MOCK_ENABLED
        original_base = settings.IRP_BASE_URL
        try:
            settings.APP_ENV = "production"
            settings.COMPLIANCE_MOCK_ENABLED = False
            settings.IRP_BASE_URL = ""
            invoice = self._invoice()
            self._enable()
            resp = self.client.post(
                f"/api/v1/invoices/{invoice['id']}/e-invoice", headers=self.headers_a
            )
            self.assertEqual(resp.status_code, 502, resp.text)
            self.assertIn("IRP_BASE_URL is not configured", resp.json()["detail"])
        finally:
            settings.APP_ENV = original_env
            settings.COMPLIANCE_MOCK_ENABLED = original_mock
            settings.IRP_BASE_URL = original_base

    def test_24_hour_cancellation_constraint(self):
        self._enable()
        invoice = self._invoice()
        invoice_id = invoice["id"]
        generated = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a
        )
        self.assertEqual(generated.status_code, 200, generated.text)
        db = SessionLocal()
        try:
            row = db.query(Invoice).filter(Invoice.id == uuid.UUID(invoice_id)).one()
            row.updated_at = datetime.utcnow() - timedelta(hours=25)
            db.commit()
        finally:
            db.close()
        late = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice/cancel",
            json={"cancel_reason": "3", "cancel_remarks": "Late cancellation"},
            headers=self.headers_a,
        )
        self.assertEqual(late.status_code, 400)
        self.assertIn("Cancellation not allowed after 24 hours", late.json()["detail"])

    def test_irp_failure_marks_invoice_failed_without_local_irn(self):
        self._enable()
        invoice = self._invoice()
        invoice_id = invoice["id"]
        with patch(
            "src.domains.taxation.einvoice_service.EInvoiceService._call_irp_generate_invoice",
            side_effect=RuntimeError("IRP unavailable"),
        ):
            result = self.client.post(
                f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a
            )
        self.assertEqual(result.status_code, 502)
        self.assertIn("IRP e-invoice generation failed", result.json()["detail"])
        db = SessionLocal()
        try:
            row = db.query(Invoice).filter(Invoice.id == uuid.UUID(invoice_id)).one()
            self.assertEqual(row.e_invoice_status, "FAILED")
            self.assertIsNone(row.irn)
            self.assertIsNone(row.qr_code)
            self.assertIn("IRP unavailable", row.e_invoice_error)
        finally:
            db.close()

    def test_tenant_boundary_isolation(self):
        self._enable()
        invoice = self._invoice()
        invoice_id = invoice["id"]
        self.assertEqual(
            self.client.post(
                f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_b
            ).status_code,
            404,
        )
        generated = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice", headers=self.headers_a
        )
        self.assertEqual(generated.status_code, 200, generated.text)
        cancel = self.client.post(
            f"/api/v1/invoices/{invoice_id}/e-invoice/cancel",
            json={"cancel_reason": "1", "cancel_remarks": "Other tenant"},
            headers=self.headers_b,
        )
        self.assertEqual(cancel.status_code, 404)


if __name__ == "__main__":
    unittest.main()
