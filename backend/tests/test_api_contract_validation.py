"""
API Contract Validation Test Suite
===================================
Validates all P0 and P1 requirements:

P0:
  1. Contact creation schema matches API contract (no HTTP 422)
  2. Product schema matches API contract
  3. Financial Year Lock enforcement (LOCKED FY blocks all postings)
  4. CRUD delete operations don't cause JSONDecodeError
  5. All delete endpoints return 204 with empty body

P1:
  6. Trial Balance always returns total_debits and total_credits
  7. Journal posting validations are consistent across entry points
  8. Account type mapping uses standard types (ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE)
  9. Auto-ledger generation creates standard accounts

Run:
    cd backend && python -m pytest tests/test_api_contract_validation.py -v
"""
import uuid
from datetime import date, timedelta
from decimal import Decimal

import pytest
from fastapi import status
from fastapi.testclient import TestClient

from src.core.database import SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Account, FinancialYear,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_TENANT_SEQ = 10_000


def _register_and_login(client: TestClient, email: str = None):
    """Register a fresh tenant, login, return (headers, tenant_id, db)."""
    global _TENANT_SEQ
    _TENANT_SEQ += 1
    email = email or f"contract_{_TENANT_SEQ}@test.com"
    client.post("/api/v1/auth/register", json={
        "email": email,
        "password": "Passw0rd!",
        "full_name": "Contract Tester",
        "company_legal_name": "ContractCo",
    })
    login = client.post("/api/v1/auth/login", json={"email": email, "password": "Passw0rd!"})
    assert login.status_code == 200, f"Login failed: {login.json()}"
    token = login.json()["access_token"]

    db = SessionLocal()
    user = db.query(User).filter(User.email == email).first()
    membership = db.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
    tenant_id = membership.tenant_id

    # Grant full permissions
    membership.permission_scopes = [
        "invoice:create", "invoice:read", "invoice:update", "invoice:delete",
        "bill:create", "bill:read", "bill:update", "bill:delete",
        "expense:create", "expense:read", "expense:edit", "expense:delete",
        "payment:create", "payment:read", "payment:update", "payment:delete",
        "ledger:view", "reports:view",
        "accounts:manage",
    ]
    db.commit()

    headers = {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant_id)}
    return headers, tenant_id, db


def _seed_accounts(client, headers):
    """Seed standard chart of accounts and return the DB session."""
    r = client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)
    assert r.status_code == 200, f"Seed failed: {r.json()}"
    db = SessionLocal()
    return db


# ---------------------------------------------------------------------------
# P0-1: Contact creation schema — must NOT return 422
# ---------------------------------------------------------------------------

class TestContactSchema:
    def test_create_customer_contact(self, client: TestClient):
        """Contact creation with valid payload returns 201, not 422."""
        headers, _, _ = _register_and_login(client, "contact_schema@test.com")
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
                "pincode": "400021",
            },
            "state_code": "27",
        }
        r = client.post("/api/v1/masters/contacts", json=payload, headers=headers)
        assert r.status_code == status.HTTP_201_CREATED, f"Expected 201, got {r.status_code}: {r.json()}"
        body = r.json()
        assert body["name"] == "Reliance Industries Ltd"
        assert body["contact_type"] == "CUSTOMER"
        assert body["state_code"] == "27"
        assert body["billing_address"]["city"] == "Mumbai"

    def test_create_vendor_contact(self, client: TestClient):
        """Vendor contact creation works correctly."""
        headers, _, _ = _register_and_login(client, "vendor_contact@test.com")
        payload = {
            "name": "Tata Consultancy Services",
            "contact_type": "VENDOR",
            "registration_type": "REGULAR",
            "billing_address": {
                "street": "TCS House, Mithona Road",
                "city": "Mumbai",
                "state": "Maharashtra",
                "state_code": "27",
                "pincode": "400001",
            },
            "state_code": "27",
        }
        r = client.post("/api/v1/masters/contacts", json=payload, headers=headers)
        assert r.status_code == status.HTTP_201_CREATED, f"Expected 201, got {r.status_code}: {r.json()}"

    def test_create_both_contact(self, client: TestClient):
        """BOTH contact type works."""
        headers, _, _ = _register_and_login(client, "both_contact@test.com")
        payload = {
            "name": "Infosys Ltd",
            "contact_type": "BOTH",
            "registration_type": "REGULAR",
            "billing_address": {
                "street": "Electronics City",
                "city": "Bangalore",
                "state": "Karnataka",
                "state_code": "29",
                "pincode": "560100",
            },
            "state_code": "29",
        }
        r = client.post("/api/v1/masters/contacts", json=payload, headers=headers)
        assert r.status_code == status.HTTP_201_CREATED

    def test_invalid_contact_type_rejected(self, client: TestClient):
        """Invalid contact_type returns 422, not 500."""
        headers, _, _ = _register_and_login(client, "bad_contact@test.com")
        payload = {
            "name": "Bad Contact",
            "contact_type": "INVALID",
            "registration_type": "CONSUMER",
            "billing_address": {
                "street": "123 Street",
                "city": "Mumbai",
                "state": "Maharashtra",
                "state_code": "27",
                "pincode": "400001",
            },
            "state_code": "27",
        }
        r = client.post("/api/v1/masters/contacts", json=payload, headers=headers)
        assert r.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY


# ---------------------------------------------------------------------------
# P0-2: Product creation schema — must NOT return 422
# ---------------------------------------------------------------------------

class TestProductSchema:
    def test_create_goods_product(self, client: TestClient):
        """Product creation with valid payload returns 201."""
        headers, _, _ = _register_and_login(client, "product_goods@test.com")
        payload = {
            "name": "Laptop Computer",
            "sku": "SKU-LAPTOP-001",
            "hsn_sac": "84716050",
            "product_type": "GOODS",
            "uom": "NOS",
            "sales_price": 65000.00,
            "purchase_price": 50000.00,
            "gst_rate": 18.0,
        }
        r = client.post("/api/v1/masters/products", json=payload, headers=headers)
        assert r.status_code == status.HTTP_201_CREATED, f"Expected 201, got {r.status_code}: {r.json()}"
        body = r.json()
        assert body["name"] == "Laptop Computer"
        assert body["product_type"] == "GOODS"
        assert body["hsn_sac"] == "84716050"

    def test_create_service_product(self, client: TestClient):
        """Service product creation works correctly."""
        headers, _, _ = _register_and_login(client, "product_svc@test.com")
        payload = {
            "name": "Consulting",
            "sku": "SRV-CONSULT",
            "hsn_sac": "998311",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 5000.00,
            "purchase_price": 0.00,
            "gst_rate": 18.0,
        }
        r = client.post("/api/v1/masters/products", json=payload, headers=headers)
        assert r.status_code == status.HTTP_201_CREATED

    def test_invalid_hsn_rejected_with_422(self, client: TestClient):
        """Non-numeric HSN code returns 422 validation error."""
        headers, _, _ = _register_and_login(client, "product_hsn@test.com")
        payload = {
            "name": "Bad HSN Product",
            "sku": "SKU-BAD",
            "hsn_sac": "9983A1",
            "product_type": "SERVICE",
            "uom": "HRS",
            "sales_price": 100.00,
            "purchase_price": 0.00,
            "gst_rate": 18.0,
        }
        r = client.post("/api/v1/masters/products", json=payload, headers=headers)
        assert r.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY


# ---------------------------------------------------------------------------
# P0-3: Financial Year Lock enforcement
# ---------------------------------------------------------------------------

class TestFinancialYearLock:
    def test_locked_fy_blocks_journal_entries(self, client: TestClient):
        """Journal entries cannot be posted to a LOCKED financial year."""
        headers, tenant_id, db = _register_and_login(client, "fylock@test.com")

        # Create FY
        r = client.post("/api/v1/financial-years", json={
            "name": "2025-26",
            "start_date": "2025-04-01",
            "end_date": "2026-03-31",
        }, headers=headers)
        fy_id = r.json()["id"]

        # Close (locks) the FY
        r = client.post(f"/api/v1/financial-years/{fy_id}/close",
                        json={"closing_date": "2026-03-31"}, headers=headers)
        assert r.status_code == 200
        assert r.json()["status"] == "LOCKED"

        # Seed accounts
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        # Find accounts
        db2 = SessionLocal()
        accounts = db2.query(Account).filter(
            Account.tenant_id == tenant_id,
            Account.deleted_at == None,
        ).all()
        cash = next((a for a in accounts if a.code == "1001"), None)
        revenue = next((a for a in accounts if a.code == "5001"), None)
        assert cash and revenue, "Seed accounts must include cash (1001) and revenue (5001)"

        # Attempt journal entry to LOCKED period — must be blocked
        r = client.post("/api/v1/accounting/journals", json={
            "entry_date": "2025-12-15",
            "description": "Should be blocked",
            "lines": [
                {"account_id": str(cash.id), "amount": 1000, "direction": "DEBIT"},
                {"account_id": str(revenue.id), "amount": 1000, "direction": "CREDIT"},
            ],
        }, headers=headers)
        assert r.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY, (
            f"Expected 422 for locked FY, got {r.status_code}: {r.json()}"
        )
        detail = r.json().get("detail", "")
        assert "locked" in detail.lower() or "locked" in str(r.json()).lower(), (
            f"Error should mention 'locked', got: {detail}"
        )
        db2.close()

    def test_locked_fy_blocks_invoice_creation(self, client: TestClient):
        """Invoices cannot be created in a LOCKED financial year."""
        headers, tenant_id, db = _register_and_login(client, "fylock_inv@test.com")

        r = client.post("/api/v1/financial-years", json={
            "name": "2025-26",
            "start_date": "2025-04-01",
            "end_date": "2026-03-31",
        }, headers=headers)
        fy_id = r.json()["id"]

        r = client.post(f"/api/v1/financial-years/{fy_id}/close",
                        json={"closing_date": "2026-03-31"}, headers=headers)
        assert r.json()["status"] == "LOCKED"

        # Seed accounts + create contact + product
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)
        r = client.post("/api/v1/masters/contacts", json={
            "name": "Test Customer",
            "contact_type": "CUSTOMER",
            "registration_type": "CONSUMER",
            "billing_address": {
                "street": "123 Street", "city": "Mumbai",
                "state": "Maharashtra", "state_code": "27", "pincode": "400001",
            },
            "state_code": "27",
        }, headers=headers)
        contact_id = r.json()["id"]

        r = client.post("/api/v1/masters/products", json={
            "name": "Test Product", "sku": "TST001", "hsn_sac": "998311",
            "product_type": "SERVICE", "uom": "HRS",
            "sales_price": 1000, "purchase_price": 0, "gst_rate": 0,
        }, headers=headers)
        product_id = r.json()["id"]

        # Try to create invoice in LOCKED period
        r = client.post("/api/v1/invoices", json={
            "contact_id": contact_id,
            "issue_date": "2025-12-15",
            "due_date": "2026-01-15",
            "pos_state_code": "27",
            "line_items": [
                {"product_id": product_id, "quantity": 1, "rate": 1000,
                 "discount": 0, "hsn_sac": "998311", "gst_rate": 0}
            ],
        }, headers=headers)
        assert r.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY, (
            f"Expected 422 for locked FY invoice, got {r.status_code}: {r.json()}"
        )
        db.close()


# ---------------------------------------------------------------------------
# P0-4: CRUD delete — no JSONDecodeError
# ---------------------------------------------------------------------------

class TestCrudDelete:
    def test_delete_contact_returns_204(self, client: TestClient):
        """DELETE returns 204 with no body — no JSONDecodeError."""
        headers, _, _ = _register_and_login(client, "del_contact@test.com")
        r = client.post("/api/v1/masters/contacts", json={
            "name": "Deletable Contact",
            "contact_type": "CUSTOMER",
            "registration_type": "CONSUMER",
            "billing_address": {
                "street": "123 St", "city": "Mumbai",
                "state": "Maharashtra", "state_code": "27", "pincode": "400001",
            },
            "state_code": "27",
        }, headers=headers)
        contact_id = r.json()["id"]

        r = client.delete(f"/api/v1/masters/contacts/{contact_id}", headers=headers)
        assert r.status_code == 204
        # Verify body is empty — this is where JSONDecodeError would occur
        assert r.text == "" or r.content == b""

    def test_delete_product_returns_204(self, client: TestClient):
        """DELETE product returns 204 with no body."""
        headers, _, _ = _register_and_login(client, "del_product@test.com")
        r = client.post("/api/v1/masters/products", json={
            "name": "Deletable Product", "sku": "DEL001",
            "hsn_sac": "998311", "product_type": "SERVICE", "uom": "HRS",
            "sales_price": 100, "purchase_price": 0, "gst_rate": 18,
        }, headers=headers)
        product_id = r.json()["id"]

        r = client.delete(f"/api/v1/masters/products/{product_id}", headers=headers)
        assert r.status_code == 204

    def test_delete_account_returns_204(self, client: TestClient):
        """DELETE account returns 204 with no body."""
        headers, _, _ = _register_and_login(client, "del_account@test.com")
        r = client.post("/api/v1/masters/accounts", json={
            "name": "Temp Account", "code": "9999",
            "account_type": "EXPENSE", "account_group": "Miscellaneous",
            "opening_balance": 0,
        }, headers=headers)
        account_id = r.json()["id"]

        r = client.delete(f"/api/v1/masters/accounts/{account_id}", headers=headers)
        assert r.status_code == 204

    def test_delete_banking_profile_returns_204(self, client: TestClient):
        """DELETE banking profile returns 204 with no body."""
        headers, _, _ = _register_and_login(client, "del_bank@test.com")
        r = client.post("/api/v1/masters/banking-profiles", json={
            "bank_name": "HDFC Bank", "account_number": "1234567890",
            "ifsc_code": "HDFC0001234", "branch_name": "Main",
            "account_holder_name": "Test Co", "account_type": "SAVINGS",
        }, headers=headers)
        assert r.status_code == 201, f"Expected 201, got {r.status_code}: {r.json()}"
        profile_id = r.json()["id"]

        r = client.delete(f"/api/v1/masters/banking-profiles/{profile_id}", headers=headers)
        assert r.status_code == 204


# ---------------------------------------------------------------------------
# P1-1: Trial Balance always returns total_debits and total_credits
# ---------------------------------------------------------------------------

class TestTrialBalanceContract:
    def test_trial_balance_has_required_fields(self, client: TestClient):
        """Trial Balance response contains total_debits and total_credits."""
        headers, _, db = _register_and_login(client, "tb_fields@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        r = client.get("/api/v1/accounting/trial-balance", headers=headers)
        assert r.status_code == 200
        body = r.json()
        assert "total_debits" in body, f"Missing total_debits in response: {list(body.keys())}"
        assert "total_credits" in body, f"Missing total_credits in response: {list(body.keys())}"
        assert "lines" in body
        assert isinstance(body["total_debits"], (int, float, str))
        assert isinstance(body["total_credits"], (int, float, str))
        db.close()

    def test_trial_balance_via_reports_has_required_fields(self, client: TestClient):
        """Reports endpoint trial balance also has total_debits and total_credits."""
        headers, _, db = _register_and_login(client, "tb_reports@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        r = client.get(
            f"/api/v1/reports/trial-balance?as_of_date={date.today().isoformat()}",
            headers=headers,
        )
        assert r.status_code == 200
        body = r.json()
        assert "total_debits" in body, f"Missing total_debits: {list(body.keys())}"
        assert "total_credits" in body, f"Missing total_credits: {list(body.keys())}"
        assert "is_balanced" in body, f"Missing is_balanced: {list(body.keys())}"
        db.close()

    def test_trial_balance_after_posting(self, client: TestClient):
        """After a journal entry, trial balance totals reflect the posting."""
        headers, tenant_id, db = _register_and_login(client, "tb_posting@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        db2 = SessionLocal()
        accounts = db2.query(Account).filter(
            Account.tenant_id == tenant_id, Account.deleted_at == None
        ).all()
        cash = next((a for a in accounts if a.code == "1001"), None)
        revenue = next((a for a in accounts if a.code == "5001"), None)

        # Post a journal entry
        r = client.post("/api/v1/accounting/journals", json={
            "entry_date": date.today().isoformat(),
            "description": "Test posting",
            "lines": [
                {"account_id": str(cash.id), "amount": 5000, "direction": "DEBIT"},
                {"account_id": str(revenue.id), "amount": 5000, "direction": "CREDIT"},
            ],
        }, headers=headers)
        assert r.status_code == 201

        # Check trial balance
        r = client.get("/api/v1/accounting/trial-balance", headers=headers)
        assert r.status_code == 200
        body = r.json()
        assert float(body["total_debits"]) > 0
        assert float(body["total_credits"]) > 0
        db2.close()
        db.close()


# ---------------------------------------------------------------------------
# P1-2: Journal posting validations are consistent
# ---------------------------------------------------------------------------

class TestJournalPostingConsistency:
    def test_manual_journal_entry_requires_balanced_lines(self, client: TestClient):
        """Journal with unbalanced debits/credits is rejected."""
        headers, tenant_id, db = _register_and_login(client, "journal_bal@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        db2 = SessionLocal()
        accounts = db2.query(Account).filter(
            Account.tenant_id == tenant_id, Account.deleted_at == None
        ).all()
        cash = next((a for a in accounts if a.code == "1001"), None)
        revenue = next((a for a in accounts if a.code == "5001"), None)

        # Unbalanced entry (debits != credits)
        r = client.post("/api/v1/accounting/journals", json={
            "entry_date": date.today().isoformat(),
            "description": "Unbalanced test",
            "lines": [
                {"account_id": str(cash.id), "amount": 5000, "direction": "DEBIT"},
                {"account_id": str(revenue.id), "amount": 3000, "direction": "CREDIT"},
            ],
        }, headers=headers)
        assert r.status_code in (status.HTTP_400_BAD_REQUEST, status.HTTP_422_UNPROCESSABLE_ENTITY), (
            f"Unbalanced journal should be rejected (400 or 422), got {r.status_code}: {r.json()}"
        )
        db2.close()
        db.close()

    def test_journal_list_returns_list(self, client: TestClient):
        """Journal list endpoint returns a list."""
        headers, _, db = _register_and_login(client, "journal_list@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        r = client.get("/api/v1/accounting/journals", headers=headers)
        assert r.status_code == 200
        assert isinstance(r.json(), list)
        db.close()


# ---------------------------------------------------------------------------
# P1-3: Account type mapping uses standard types
# ---------------------------------------------------------------------------

class TestAccountTypeMapping:
    def test_seed_creates_standard_account_types(self, client: TestClient):
        """Auto-seeded accounts use ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE."""
        headers, tenant_id, db = _register_and_login(client, "acct_types@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        db2 = SessionLocal()
        accounts = db2.query(Account).filter(
            Account.tenant_id == tenant_id, Account.deleted_at == None
        ).all()
        valid_types = {"ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE"}
        for a in accounts:
            assert a.account_type in valid_types, (
                f"Account '{a.name}' has unexpected type '{a.account_type}'"
            )

        # Verify each standard type exists
        types_found = {a.account_type for a in accounts}
        assert "ASSET" in types_found, "No ASSET accounts found"
        assert "LIABILITY" in types_found, "No LIABILITY accounts found"
        assert "REVENUE" in types_found, "No REVENUE accounts found"
        assert "EXPENSE" in types_found, "No EXPENSE accounts found"
        db2.close()
        db.close()

    def test_auto_ledger_creates_gst_accounts(self, client: TestClient):
        """Auto-ledger creates GST Input (ASSET) and GST Output (LIABILITY)."""
        headers, tenant_id, db = _register_and_login(client, "gst_accounts@test.com")
        client.post("/api/v1/masters/accounts/seed-defaults", headers=headers)

        db2 = SessionLocal()
        accounts = db2.query(Account).filter(
            Account.tenant_id == tenant_id, Account.deleted_at == None
        ).all()
        acc_map = {a.code: a for a in accounts}

        # GST Input Tax = ASSET (CGST Input Tax, etc.)
        assert "1401" in acc_map, "Missing CGST Input Tax account"
        assert acc_map["1401"].account_type == "ASSET"
        assert "1402" in acc_map, "Missing SGST Input Tax account"
        assert acc_map["1402"].account_type == "ASSET"

        # GST Output Tax = LIABILITY (CGST Output Tax, etc.)
        assert "3001" in acc_map, "Missing CGST Output Tax account"
        assert acc_map["3001"].account_type == "LIABILITY"
        assert "3002" in acc_map, "Missing SGST Output Tax account"
        assert acc_map["3002"].account_type == "LIABILITY"

        db2.close()
        db.close()
