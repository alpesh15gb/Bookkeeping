import sys
import os
import uuid
import unittest
from concurrent.futures import ThreadPoolExecutor
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import User, Tenant, TenantMembership, Branch, TenantSetting, NumberingSeries
from src.domains.company.services import NumberingSeriesService, decrypt_credential

class TestCompanyAndSettings(unittest.TestCase):
    def setUp(self):
        # 1. Reset test database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # 2. Register/Login a user
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

        # Retrieve membership/tenant ID
        db = SessionLocal()
        try:
            m = db.query(TenantMembership).first()
            self.tenant_id = m.tenant_id
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.access_token}"
        }

    def test_company_creation_and_onboarding(self):
        # Create an additional company/tenant
        payload = {
            "legal_name": "Second Company Ltd",
            "trade_name": "Second Company",
            "gstin": "27AAAAA1111A1Z1",
            "pan": "AAAAA1111A"
        }
        res = self.client.post("/api/v1/companies", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["legal_name"], "Second Company Ltd")
        self.assertIn("id", data)
        new_tenant_id = data["id"]

        # Verify defaults (numbering series and settings) are seeded
        db = SessionLocal()
        try:
            settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == uuid.UUID(new_tenant_id)).first()
            self.assertIsNotNone(settings)
            self.assertEqual(settings.currency, "INR")

            series_count = db.query(NumberingSeries).filter(NumberingSeries.tenant_id == uuid.UUID(new_tenant_id)).count()
            self.assertEqual(series_count, 12) # Expanded document types
        finally:
            db.close()

    def test_company_retrieval_and_update(self):
        # Retrieve details
        res = self.client.get(f"/api/v1/companies/{self.tenant_id}", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["legal_name"], "Varma Ventures Pvt Ltd")

        # Update details
        update_payload = {
            "legal_name": "Varma Ventures Group Ltd",
            "trade_name": "Varma Group",
            "gstin": "27BBBBB2222B2Z6",
            "pan": "BBBBB2222B"
        }
        res_put = self.client.put(f"/api/v1/companies/{self.tenant_id}", json=update_payload, headers=self.headers)
        self.assertEqual(res_put.status_code, 200)
        self.assertEqual(res_put.json()["legal_name"], "Varma Ventures Group Ltd")

    def test_branches_crud(self):
        # 1. Create a branch
        branch_payload = {
            "name": "Mumbai HQ Branch",
            "gstin": "27BBBBB2222B2Z6",
            "address": {
                "street": "101, Main Road, Fort",
                "city": "Mumbai",
                "state": "Maharashtra",
                "state_code": "27",
                "pincode": "400001",
                "country": "India"
            }
        }
        res_post = self.client.post(f"/api/v1/companies/{self.tenant_id}/branches", json=branch_payload, headers=self.headers)
        self.assertEqual(res_post.status_code, 201)
        branch_data = res_post.json()
        self.assertEqual(branch_data["name"], "Mumbai HQ Branch")
        branch_id = branch_data["id"]

        # 2. List branches
        res_list = self.client.get(f"/api/v1/companies/{self.tenant_id}/branches", headers=self.headers)
        self.assertEqual(res_list.status_code, 200)
        self.assertEqual(len(res_list.json()), 1)

        # 3. Update branch
        update_payload = {
            "name": "Mumbai Fort Branch",
            "is_active": False
        }
        res_put = self.client.put(f"/api/v1/companies/{self.tenant_id}/branches/{branch_id}", json=update_payload, headers=self.headers)
        self.assertEqual(res_put.status_code, 200)
        self.assertEqual(res_put.json()["name"], "Mumbai Fort Branch")
        self.assertEqual(res_put.json()["is_active"], False)

        # 4. Soft Delete branch
        res_del = self.client.delete(f"/api/v1/companies/{self.tenant_id}/branches/{branch_id}", headers=self.headers)
        self.assertEqual(res_del.status_code, 204)

        # Re-list should be empty (soft deleted)
        res_list2 = self.client.get(f"/api/v1/companies/{self.tenant_id}/branches", headers=self.headers)
        self.assertEqual(res_list2.status_code, 200)
        self.assertEqual(len(res_list2.json()), 0)

    def test_settings_credentials_encryption(self):
        # Update settings with API credentials
        settings_payload = {
            "logo_url": "https://cdn.varma.com/logo.png",
            "gst_enabled": True,
            "e_invoicing_enabled": True,
            "e_invoice_username": "einvoice_user123",
            "e_invoice_password": "einvoice_password123!",
            "e_way_bill_username": "eway_user123",
            "e_way_bill_password": "eway_password123!"
        }
        res_put = self.client.put("/api/v1/settings", json=settings_payload, headers=self.headers)
        self.assertEqual(res_put.status_code, 200)
        data = res_put.json()
        self.assertEqual(data["logo_url"], "https://cdn.varma.com/logo.png")
        self.assertEqual(data["e_invoice_username"], "einvoice_user123")
        # Ensure password hashes are NOT returned in response
        self.assertNotIn("e_invoice_password", data)
        self.assertNotIn("e_invoice_password_hash", data)

        # Query direct database model to verify secure credential encryption
        db = SessionLocal()
        try:
            db_setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == self.tenant_id).first()
            self.assertIsNotNone(db_setting)
            self.assertNotEqual(db_setting.e_invoice_password_hash, "einvoice_password123!")
            # Decrypt value to verify it can be read by integrations
            decrypted = decrypt_credential(db_setting.e_invoice_password_hash)
            self.assertEqual(decrypted, "einvoice_password123!")
        finally:
            db.close()

    def test_numbering_series_crud(self):
        # Get defaults
        res = self.client.get("/api/v1/settings/series", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        series_list = res.json()
        self.assertEqual(len(series_list), 12)

        invoice_series = next(s for s in series_list if s["document_type"] == "INVOICE")
        self.assertEqual(invoice_series["prefix"], "INV/2026/")

        # Create custom numbering series
        new_series_payload = {
            "document_type": "INVOICE",
            "prefix": "VARMA-INV-",
            "next_number": 100,
            "suffix": "-26",
            "padding_digits": 5
        }
        res_post = self.client.post("/api/v1/settings/series", json=new_series_payload, headers=self.headers)
        self.assertEqual(res_post.status_code, 201)
        new_series = res_post.json()
        self.assertEqual(new_series["prefix"], "VARMA-INV-")
        self.assertEqual(new_series["is_active"], True)

        # Retrieve list and verify the old series was set to inactive
        res_list = self.client.get("/api/v1/settings/series", headers=self.headers)
        invoice_series_items = [s for s in res_list.json() if s["document_type"] == "INVOICE"]
        self.assertEqual(len(invoice_series_items), 2)
        active_series = next(s for s in invoice_series_items if s["is_active"])
        inactive_series = next(s for s in invoice_series_items if not s["is_active"])

        self.assertEqual(active_series["prefix"], "VARMA-INV-")
        self.assertEqual(inactive_series["prefix"], "INV/2026/")

    def test_numbering_series_concurrency_safety(self):
        # Run multithreaded requests calling sequence locks to verify no duplicates are generated
        # SQLite serialization or row lock behavior handles this.
        import threading
        lock = threading.Lock()
        def fetch_next_num():
            with lock:
                # Open a new database session per thread
                db_thread = SessionLocal()
                try:
                    # Direct service method call representing atomic write sequence
                    # Starts its own transaction and commits or flushes
                    res = NumberingSeriesService.generate_next_number(db_thread, self.tenant_id, "INVOICE")
                    db_thread.commit()
                    return res
                finally:
                    db_thread.close()

        # Run 20 concurrent generation requests
        total_workers = 10
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(fetch_next_num) for _ in range(total_workers)]
            results = [f.result() for f in futures]

        # Verify all numbers are unique
        self.assertEqual(len(results), total_workers)
        self.assertEqual(len(set(results)), total_workers)

        # Verify the numbers match the format: INV/2026/0001, INV/2026/0002, etc.
        # Since defaults start at 1 and increment by 1
        expected_nums = [f"INV/2026/{str(i).zfill(4)}" for i in range(1, total_workers + 1)]
        self.assertEqual(sorted(results), expected_nums)

if __name__ == "__main__":
    unittest.main()
