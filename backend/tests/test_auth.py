import sys
import os
import uuid
import unittest
from datetime import date
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import User, Tenant, TenantMembership

class TestAuthentication(unittest.TestCase):
    def setUp(self):
        # 1. Reset test database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

    def test_auth_registration_and_login_flow(self):
        # 1. Register a new user
        reg_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma",
            "phone_number": "+919999988888",
            "company_legal_name": "Varma Ventures Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z6",
            "company_pan": "BBBBB2222B"
        }
        res_reg = self.client.post("/api/v1/auth/register", json=reg_payload)
        self.assertEqual(res_reg.status_code, 201)
        user_data = res_reg.json()
        self.assertEqual(user_data["email"], "owner@company.com")
        self.assertEqual(user_data["full_name"], "Vijay Varma")
        self.assertIn("id", user_data)

        # 2. Authenticate with credentials
        login_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!"
        }
        res_login = self.client.post("/api/v1/auth/login", json=login_payload)
        self.assertEqual(res_login.status_code, 200)
        token_data = res_login.json()
        self.assertIn("access_token", token_data)
        self.assertIn("refresh_token", token_data)
        self.assertEqual(token_data["token_type"], "bearer")
        
        access_token = token_data["access_token"]
        refresh_token = token_data["refresh_token"]

        # 3. Refresh Access Token
        res_ref = self.client.post(f"/api/v1/auth/refresh?refresh_token={refresh_token}")
        self.assertEqual(res_ref.status_code, 200)
        new_token_data = res_ref.json()
        self.assertIn("access_token", new_token_data)

        # 4. Verify Identity
        auth_headers = {"Authorization": f"Bearer {access_token}"}
        res_me = self.client.get("/api/v1/auth/me", headers=auth_headers)
        self.assertEqual(res_me.status_code, 200)
        me_data = res_me.json()
        self.assertEqual(me_data["email"], "owner@company.com")

    def test_tenant_context_rls_guard(self):
        # 1. Register Owner 1
        reg1 = {
            "email": "user1@company.com",
            "password": "Password1!",
            "full_name": "User One",
            "company_legal_name": "Company One"
        }
        res_reg1 = self.client.post("/api/v1/auth/register", json=reg1)
        self.assertEqual(res_reg1.status_code, 201)
        user1_id = res_reg1.json()["id"]

        # Log in User 1
        login1 = {"email": "user1@company.com", "password": "Password1!"}
        token1 = self.client.post("/api/v1/auth/login", json=login1).json()["access_token"]

        # Locate Tenant ID created for User 1
        db = SessionLocal()
        try:
            m1 = db.query(TenantMembership).filter(TenantMembership.user_id == uuid.UUID(user1_id)).first()
            tenant1_id = str(m1.tenant_id)
        finally:
            db.close()

        # 2. Register Owner 2
        reg2 = {
            "email": "user2@company.com",
            "password": "Password2!",
            "full_name": "User Two",
            "company_legal_name": "Company Two"
        }
        self.client.post("/api/v1/auth/register", json=reg2)
        
        # Log in User 2
        login2 = {"email": "user2@company.com", "password": "Password2!"}
        token2 = self.client.post("/api/v1/auth/login", json=login2).json()["access_token"]

        # 3. Test multi-tenant isolation: User 2 tries to query User 1's Tenant ID
        headers = {
            "Authorization": f"Bearer {token2}",
            "X-Tenant-ID": tenant1_id
        }
        # Attempt to access invoices under Tenant 1 using User 2's session
        res_fail = self.client.get("/api/v1/invoices", headers=headers)
        self.assertEqual(res_fail.status_code, 403) # Must be 403 Forbidden!
        
        # Success check: User 1 queries own Tenant
        headers_ok = {
            "Authorization": f"Bearer {token1}",
            "X-Tenant-ID": tenant1_id
        }
        res_ok = self.client.get("/api/v1/invoices", headers=headers_ok)
        self.assertEqual(res_ok.status_code, 200)

if __name__ == "__main__":
    unittest.main()
