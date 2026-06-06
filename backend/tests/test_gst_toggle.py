"""E2E test for GST Enable/Disable system."""
import pytest
import uuid
from datetime import date
from fastapi.testclient import TestClient
from src.core.database import SessionLocal
from src.infrastructure.database.models import User, TenantMembership


class TestGstToggle:
    """Tests for GST mode toggle and backend enforcement."""

    def _register_and_login(self, client: TestClient, email="gst_toggle_test@example.com"):
        """Register a user, login, and return (headers, tenant_id)."""
        client.post("/api/v1/auth/register", json={
            "email": email,
            "password": "Passw0rd!",
            "full_name": "GST Toggle Test User",
            "company_legal_name": "GST Test Co",
        })
        login = client.post("/api/v1/auth/login", json={"email": email, "password": "Passw0rd!"})
        assert login.status_code == 200
        token = login.json()["access_token"]

        db = SessionLocal()
        try:
            uid = db.query(User).filter(User.email == email).first().id
            m = db.query(TenantMembership).filter(TenantMembership.user_id == uid).first()
            tenant_id = m.tenant_id
        finally:
            db.close()

        headers = {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant_id)}
        return headers, str(tenant_id)

    def test_toggle_gst_mode(self, client: TestClient):
        headers, tid = self._register_and_login(client)

        res = client.get(f"/api/v1/companies/{tid}", headers=headers)
        assert res.status_code == 200
        data = res.json()
        assert data['tax_mode'] == 'NON_GST'
        assert data['gst_enabled'] is False

        res = client.post(
            f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "GST_REGULAR"},
            headers=headers,
        )
        assert res.status_code == 200
        data = res.json()
        assert data['tax_mode'] == 'GST_REGULAR'
        assert data['gst_enabled'] is True

        res = client.get(f"/api/v1/companies/{tid}", headers=headers)
        assert res.status_code == 200
        assert res.json()['tax_mode'] == 'GST_REGULAR'
        assert res.json()['gst_enabled'] is True

        res = client.post(
            f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "NON_GST"},
            headers=headers,
        )
        assert res.status_code == 200
        assert res.json()['tax_mode'] == 'NON_GST'
        assert res.json()['gst_enabled'] is False

    def test_disable_gst_preserves_company_data(self, client: TestClient):
        headers, tid = self._register_and_login(client)

        res = client.post(
            f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "NON_GST"},
            headers=headers,
        )
        assert res.status_code == 200

        res = client.get(f"/api/v1/companies/{tid}", headers=headers)
        assert res.status_code == 200
        assert res.json()['legal_name'] == 'GST Test Co'

    def test_invalid_tax_mode_rejected(self, client: TestClient):
        headers, tid = self._register_and_login(client)

        res = client.post(
            f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "INVALID_MODE"},
            headers=headers,
        )
        assert res.status_code == 422

    def test_gst_rate_forced_zero_when_non_gst(self, client: TestClient):
        headers, tid = self._register_and_login(client, "gst_invoice_test@example.com")

        client.post(
            f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "NON_GST"},
            headers=headers,
        )

        contact_res = client.post(
            "/api/v1/masters/contacts",
            json={
                "name": "GST Test Contact",
                "contact_type": "CUSTOMER",
                "state_code": "27",
                "billing_address": {
                    "street": "123 Test St",
                    "city": "Mumbai",
                    "state": "Maharashtra",
                    "state_code": "27",
                    "pincode": "400001",
                },
            },
            headers=headers,
        )
        assert contact_res.status_code == 201
        contact_id = contact_res.json()['id']

        prod_res = client.post(
            "/api/v1/masters/products",
            json={
                "name": "GST Test Product",
                "product_type": "GOODS",
                "uom": "NOS",
                "sales_price": 1000,
                "purchase_price": 500,
                "hsn_sac": "998311",
                "gst_rate": 18,
                "opening_stock": 1000,
            },
            headers=headers,
        )
        assert prod_res.status_code == 201
        product_id = prod_res.json()['id']

        inv_res = client.post(
            "/api/v1/invoices",
            json={
                "contact_id": contact_id,
                "issue_date": "2026-06-06",
                "due_date": "2026-07-06",
                "pos_state_code": "27",
                "line_items": [
                    {
                        "product_id": product_id,
                        "description": "Test Item",
                        "quantity": 1,
                        "rate": 1000,
                        "discount": 0,
                        "hsn_sac": "998311",
                        "gst_rate": 18,
                    }
                ],
            },
            headers=headers,
        )
        assert inv_res.status_code == 201
        inv = inv_res.json()
        line = inv['lines'][0]
        assert float(line['gst_rate']) == 0.0
        assert float(line['cgst_amount']) == 0.0
        assert float(line['sgst_amount']) == 0.0
        assert float(line['igst_amount']) == 0.0
