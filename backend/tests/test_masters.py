import sys
import os
import uuid
import unittest
from datetime import date
from decimal import Decimal
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import User, Tenant, TenantMembership, Account, BankingProfile, ExpenseCategory

class TestMasterData(unittest.TestCase):
    def setUp(self):
        # 1. Reset database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        # Seed global TaxTemplate and PaymentTerm defaults for testing
        from src.infrastructure.database.models import TaxTemplate, PaymentTerm
        db_seed = SessionLocal()
        try:
            db_seed.add_all([
                TaxTemplate(name="GST 0%", rate=Decimal("0.00")),
                TaxTemplate(name="GST 5%", rate=Decimal("5.00")),
                TaxTemplate(name="GST 12%", rate=Decimal("12.00")),
                TaxTemplate(name="GST 18%", rate=Decimal("18.00")),
                TaxTemplate(name="GST 28%", rate=Decimal("28.00"))
            ])
            db_seed.add_all([
                PaymentTerm(name="Due on Receipt", due_days=0),
                PaymentTerm(name="Net 15", due_days=15),
                PaymentTerm(name="Net 30", due_days=30),
                PaymentTerm(name="Net 60", due_days=60)
            ])
            db_seed.commit()
        finally:
            db_seed.close()

        self.client = TestClient(app)

        # 2. Register/Login Tenant A
        reg_a = {
            "email": "userA@company.com",
            "password": "Password1!",
            "full_name": "User A",
            "company_legal_name": "Company A",
            "company_gstin": "27AAAAA1111A1Z1"
        }
        self.client.post("/api/v1/auth/register", json=reg_a)
        token_a = self.client.post("/api/v1/auth/login", json={"email": "userA@company.com", "password": "Password1!"}).json()["access_token"]
        
        # 3. Register/Login Tenant B
        reg_b = {
            "email": "userB@company.com",
            "password": "Password2!",
            "full_name": "User B",
            "company_legal_name": "Company B"
        }
        self.client.post("/api/v1/auth/register", json=reg_b)
        token_b = self.client.post("/api/v1/auth/login", json={"email": "userB@company.com", "password": "Password2!"}).json()["access_token"]

        db = SessionLocal()
        try:
            mA = db.query(TenantMembership).join(User).filter(User.email == "userA@company.com").first()
            self.tenant_a_id = mA.tenant_id
            
            mB = db.query(TenantMembership).join(User).filter(User.email == "userB@company.com").first()
            self.tenant_b_id = mB.tenant_id
        finally:
            db.close()

        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a_id),
            "Authorization": f"Bearer {token_a}"
        }
        self.headers_b = {
            "X-Tenant-ID": str(self.tenant_b_id),
            "Authorization": f"Bearer {token_b}"
        }

    def test_contacts_crud_and_tenant_isolation(self):
        # Create customer in Tenant A
        payload = {
            "name": "Reliance Industries Ltd",
            "email": "finance@ril.com",
            "phone": "+912235555000",
            "contact_type": "CUSTOMER",
            "gstin": "27AAACR1234H1Z5",
            "pan": "AAACR1234H",
            "registration_type": "REGULAR",
            "billing_address": {
                "street": "Maker Chambers IV, Nariman Point",
                "city": "Mumbai",
                "state": "Maharashtra",
                "state_code": "27",
                "pincode": "400021"
            },
            "state_code": "27"
        }
        res_post = self.client.post("/api/v1/masters/contacts", json=payload, headers=self.headers_a)
        self.assertEqual(res_post.status_code, 201)
        contact_id = res_post.json()["id"]

        # Tenant A can list it
        res_list = self.client.get("/api/v1/masters/contacts", headers=self.headers_a)
        self.assertEqual(len(res_list.json()), 1)
        self.assertEqual(res_list.json()[0]["name"], "Reliance Industries Ltd")

        # Tenant B cannot list it (should be empty list)
        res_list_b = self.client.get("/api/v1/masters/contacts", headers=self.headers_b)
        self.assertEqual(len(res_list_b.json()), 0)

        # Tenant B trying to retrieve Tenant A's contact gets 404
        res_get_b = self.client.get(f"/api/v1/masters/contacts/{contact_id}", headers=self.headers_b)
        self.assertEqual(res_get_b.status_code, 404)

        # Update contact in Tenant A
        update_payload = {
            "name": "Reliance Industries Group",
            "phone": "+912235555001"
        }
        res_put = self.client.put(f"/api/v1/masters/contacts/{contact_id}", json=update_payload, headers=self.headers_a)
        self.assertEqual(res_put.status_code, 200)
        self.assertEqual(res_put.json()["name"], "Reliance Industries Group")

        # Delete contact in Tenant A
        res_del = self.client.delete(f"/api/v1/masters/contacts/{contact_id}", headers=self.headers_a)
        self.assertEqual(res_del.status_code, 204)

        # Retrieve deleted contact should fail
        res_get_del = self.client.get(f"/api/v1/masters/contacts/{contact_id}", headers=self.headers_a)
        self.assertEqual(res_get_del.status_code, 404)

    def test_products_crud_and_validation(self):
        payload = {
            "name": "Consulting Hourly Rate",
            "sku": "SRV-CONSULT",
            "hsn_sac": "998311", # 6 digit SAC
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 5000.00,
            "purchase_price": 0.00,
            "gst_rate": 18.0
        }
        res_post = self.client.post("/api/v1/masters/products", json=payload, headers=self.headers_a)
        self.assertEqual(res_post.status_code, 201)
        product_id = res_post.json()["id"]

        # Validate invalid HSN code format (non-digit)
        invalid_payload = payload.copy()
        invalid_payload["hsn_sac"] = "9983A1"
        res_post_inv = self.client.post("/api/v1/masters/products", json=invalid_payload, headers=self.headers_a)
        self.assertEqual(res_post_inv.status_code, 422)

        # Read product
        res_get = self.client.get(f"/api/v1/masters/products/{product_id}", headers=self.headers_a)
        self.assertEqual(res_get.status_code, 200)
        self.assertEqual(float(res_get.json()["sales_price"]), 5000.00)

    def test_chart_of_accounts_crud(self):
        # Create parent account
        parent_payload = {
            "name": "Current Assets",
            "code": "1000",
            "account_type": "ASSET",
            "opening_balance": 0.00
        }
        res_p = self.client.post("/api/v1/masters/accounts", json=parent_payload, headers=self.headers_a)
        self.assertEqual(res_p.status_code, 201)
        parent_id = res_p.json()["id"]

        # Create child account
        child_payload = {
            "name": "HDFC Bank Account",
            "code": "1001",
            "account_type": "ASSET",
            "parent_id": parent_id,
            "opening_balance": 150000.00
        }
        res_c = self.client.post("/api/v1/masters/accounts", json=child_payload, headers=self.headers_a)
        self.assertEqual(res_c.status_code, 201)
        child_id = res_c.json()["id"]

        # Verify child current balance is same as opening balance
        self.assertEqual(float(res_c.json()["current_balance"]), 150000.00)
        self.assertEqual(res_c.json()["parent_id"], parent_id)

        # Assert duplicate code gets rejected
        dup_payload = {
            "name": "SBI Bank Account",
            "code": "1001",
            "account_type": "ASSET",
            "opening_balance": 0.00
        }
        res_dup = self.client.post("/api/v1/masters/accounts", json=dup_payload, headers=self.headers_a)
        self.assertEqual(res_dup.status_code, 400)

        # Update opening balance and verify current balance shifts accordingly
        put_payload = {
            "opening_balance": 200000.00
        }
        res_put = self.client.put(f"/api/v1/masters/accounts/{child_id}", json=put_payload, headers=self.headers_a)
        self.assertEqual(res_put.status_code, 200)
        self.assertEqual(float(res_put.json()["current_balance"]), 200000.00)

    def test_banking_profiles_primary_logic(self):
        # Create bank profile 1
        bank1 = {
            "bank_name": "HDFC Bank",
            "account_number": "50001002003004",
            "ifsc_code": "HDFC0000001",
            "account_holder_name": "Varma Ventures Pvt Ltd",
            "upi_id": "varma@hdfc",
            "is_primary": True
        }
        res1 = self.client.post("/api/v1/masters/banking-profiles", json=bank1, headers=self.headers_a)
        self.assertEqual(res1.status_code, 201)
        profile1_id = res1.json()["id"]

        # Create bank profile 2 (also is_primary=True)
        bank2 = {
            "bank_name": "ICICI Bank",
            "account_number": "100020003000",
            "ifsc_code": "ICIC0000002",
            "account_holder_name": "Varma Ventures Pvt Ltd",
            "upi_id": "varma@icici",
            "is_primary": True
        }
        res2 = self.client.post("/api/v1/masters/banking-profiles", json=bank2, headers=self.headers_a)
        self.assertEqual(res2.status_code, 201)
        profile2_id = res2.json()["id"]

        # Verify profile 1 is no longer primary, and profile 2 is primary
        res1_get = self.client.get(f"/api/v1/masters/banking-profiles/{profile1_id}", headers=self.headers_a)
        res2_get = self.client.get(f"/api/v1/masters/banking-profiles/{profile2_id}", headers=self.headers_a)

        self.assertFalse(res1_get.json()["is_primary"])
        self.assertTrue(res2_get.json()["is_primary"])

    def test_expense_categories_linking(self):
        # Create a ledger account first
        acc_payload = {
            "name": "Rent Expenses",
            "code": "4001",
            "account_type": "EXPENSE",
            "opening_balance": 0.00
        }
        acc_id = self.client.post("/api/v1/masters/accounts", json=acc_payload, headers=self.headers_a).json()["id"]

        # Create expense category
        cat_payload = {
            "name": "Office Rent",
            "description": "Monthly rent for fort head office",
            "linked_account_id": acc_id
        }
        res = self.client.post("/api/v1/masters/expense-categories", json=cat_payload, headers=self.headers_a)
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.json()["linked_account_id"], acc_id)

    def test_tax_templates_and_payment_terms_seeding(self):
        # Retrieve tax templates
        res_tax = self.client.get("/api/v1/masters/tax-templates", headers=self.headers_a)
        self.assertEqual(res_tax.status_code, 200)
        self.assertGreaterEqual(len(res_tax.json()), 5) # GST 0%, 5%, 12%, 18%, 28%

        # Retrieve payment terms
        res_terms = self.client.get("/api/v1/masters/payment-terms", headers=self.headers_a)
        self.assertEqual(res_terms.status_code, 200)
        self.assertGreaterEqual(len(res_terms.json()), 4) # Due on Receipt, Net 15, Net 30, Net 60

if __name__ == "__main__":
    unittest.main()
