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
from src.infrastructure.database.models import User, Tenant, TenantMembership, Account, JournalEntry, JournalLine

class TestAccountingFlow(unittest.TestCase):
    def setUp(self):
        # Reset database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # 1. Register Tenant A
        reg_payload_a = {
            "email": "owner_a@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma A",
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

        # 2. Register Tenant B
        reg_payload_b = {
            "email": "owner_b@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma B",
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

        # Fetch tenant IDs and seed Chart of Accounts
        db = SessionLocal()
        try:
            m_a = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_a@company.com").first().id).first()
            self.tenant_a_id = m_a.tenant_id

            m_b = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_b@company.com").first().id).first()
            self.tenant_b_id = m_b.tenant_id

            # Seed accounts for Tenant A
            self.cash_acc = Account(
                tenant_id=self.tenant_a_id,
                name="Cash A/c",
                code="10001",
                account_type="ASSET",
                opening_balance=Decimal("1000.00"),
                current_balance=Decimal("1000.00"),
                is_active=True
            )
            self.bank_acc = Account(
                tenant_id=self.tenant_a_id,
                name="Bank A/c",
                code="10002",
                account_type="ASSET",
                opening_balance=Decimal("5000.00"),
                current_balance=Decimal("5000.00"),
                is_active=True
            )
            self.revenue_acc = Account(
                tenant_id=self.tenant_a_id,
                name="Sales Revenue",
                code="30001",
                account_type="REVENUE",
                opening_balance=Decimal("0.00"),
                current_balance=Decimal("0.00"),
                is_active=True
            )
            self.rent_acc = Account(
                tenant_id=self.tenant_a_id,
                name="Rent Expense",
                code="40001",
                account_type="EXPENSE",
                opening_balance=Decimal("0.00"),
                current_balance=Decimal("0.00"),
                is_active=True
            )
            self.equity_acc = Account(
                tenant_id=self.tenant_a_id,
                name="Owner Equity",
                code="20001",
                account_type="EQUITY",
                opening_balance=Decimal("6000.00"),
                current_balance=Decimal("6000.00"),
                is_active=True
            )

            db.add_all([self.cash_acc, self.bank_acc, self.revenue_acc, self.rent_acc, self.equity_acc])
            db.commit()

            # Refresh to populate IDs
            db.refresh(self.cash_acc)
            db.refresh(self.bank_acc)
            db.refresh(self.revenue_acc)
            db.refresh(self.rent_acc)
            db.refresh(self.equity_acc)

            self.cash_id = self.cash_acc.id
            self.bank_id = self.bank_acc.id
            self.revenue_id = self.revenue_acc.id
            self.rent_id = self.rent_acc.id
            self.equity_id = self.equity_acc.id
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

    def test_journal_creation_and_balance_verification(self):
        # 1. Post a manual Journal Entry: Pay rent (1200) from Bank
        # Debit: Rent Expense (1200), Credit: Bank (1200)
        payload = {
            "entry_date": str(date.today()),
            "description": "Office rent payment",
            "lines": [
                {"account_id": str(self.rent_id), "amount": 1200.00, "direction": "DEBIT", "narration": "Rent for May"},
                {"account_id": str(self.bank_id), "amount": 1200.00, "direction": "CREDIT", "narration": "Paid via HDFC"}
            ]
        }
        res = self.client.post("/api/v1/accounting/journals", json=payload, headers=self.headers_a)
        self.assertEqual(res.status_code, 201)
        jv = res.json()

        self.assertTrue(jv["reference_number"].startswith("JV/2026/"))
        self.assertEqual(len(jv["lines"]), 2)

        # 2. Check updated current balances of both accounts
        db = SessionLocal()
        try:
            rent_account = db.query(Account).filter(Account.id == self.rent_id).first()
            bank_account = db.query(Account).filter(Account.id == self.bank_id).first()
            self.assertEqual(float(rent_account.current_balance), 1200.00)
            self.assertEqual(float(bank_account.current_balance), 3800.00) # 5000 - 1200
        finally:
            db.close()

        # 3. Test validation rules: unbalanced entry
        payload_unbalanced = {
            "entry_date": str(date.today()),
            "description": "Unbalanced entry",
            "lines": [
                {"account_id": str(self.rent_id), "amount": 1000.00, "direction": "DEBIT"},
                {"account_id": str(self.bank_id), "amount": 800.00, "direction": "CREDIT"}
            ]
        }
        res_unb = self.client.post("/api/v1/accounting/journals", json=payload_unbalanced, headers=self.headers_a)
        self.assertEqual(res_unb.status_code, 400)

        # 4. Test validation rules: single line
        payload_single = {
            "entry_date": str(date.today()),
            "description": "Single line entry",
            "lines": [
                {"account_id": str(self.rent_id), "amount": 1000.00, "direction": "DEBIT"}
            ]
        }
        res_sin = self.client.post("/api/v1/accounting/journals", json=payload_single, headers=self.headers_a)
        self.assertEqual(res_sin.status_code, 400)

    def test_ledger_running_balance(self):
        # Post Rent payment (1200)
        payload = {
            "entry_date": str(date.today()),
            "description": "Rent payment",
            "lines": [
                {"account_id": str(self.rent_id), "amount": 1200.00, "direction": "DEBIT"},
                {"account_id": str(self.bank_id), "amount": 1200.00, "direction": "CREDIT"}
            ]
        }
        self.client.post("/api/v1/accounting/journals", json=payload, headers=self.headers_a)

        # Fetch ledger card for Bank A/c
        res_ledger = self.client.get(f"/api/v1/accounting/ledger/{self.bank_id}", headers=self.headers_a)
        self.assertEqual(res_ledger.status_code, 200)
        report = res_ledger.json()

        self.assertEqual(float(report["opening_balance"]), 5000.00)
        self.assertEqual(len(report["lines"]), 1)
        self.assertEqual(float(report["lines"][0]["credit_amount"]), 1200.00)
        self.assertEqual(float(report["lines"][0]["debit_amount"]), 0.00)
        self.assertEqual(float(report["lines"][0]["running_balance"]), 3800.00)
        self.assertEqual(float(report["closing_balance"]), 3800.00)

    def test_trial_balance_and_profit_loss(self):
        # 1. Post rent expense: Debit Rent (1200), Credit Bank (1200)
        payload1 = {
            "entry_date": str(date.today()),
            "description": "Rent",
            "lines": [
                {"account_id": str(self.rent_id), "amount": 1200.00, "direction": "DEBIT"},
                {"account_id": str(self.bank_id), "amount": 1200.00, "direction": "CREDIT"}
            ]
        }
        self.client.post("/api/v1/accounting/journals", json=payload1, headers=self.headers_a)

        # 2. Post sales receipt: Debit Cash (2500), Credit Sales Revenue (2500)
        payload2 = {
            "entry_date": str(date.today()),
            "description": "Consultancy sales",
            "lines": [
                {"account_id": str(self.cash_id), "amount": 2500.00, "direction": "DEBIT"},
                {"account_id": str(self.revenue_id), "amount": 2500.00, "direction": "CREDIT"}
            ]
        }
        self.client.post("/api/v1/accounting/journals", json=payload2, headers=self.headers_a)

        # 3. Retrieve Trial Balance
        res_tb = self.client.get("/api/v1/accounting/trial-balance", headers=self.headers_a)
        self.assertEqual(res_tb.status_code, 200)
        tb = res_tb.json()

        # Check total balancing
        self.assertEqual(float(tb["total_opening_debits"]), 6000.00)  # Cash (1000) + Bank (5000)
        self.assertEqual(float(tb["total_opening_credits"]), 6000.00) # Equity (6000)
        self.assertEqual(float(tb["total_debits"]), 3700.00)          # Rent (1200) + Cash (2500)
        self.assertEqual(float(tb["total_credits"]), 3700.00)         # Bank (1200) + Revenue (2500)
        
        # Closing balances calculation:
        # Cash: 1000 + 2500 = 3500 (debit)
        # Bank: 5000 - 1200 = 3800 (debit)
        # Rent: 0 + 1200 = 1200 (debit)
        # Total closing debits = 3500 + 3800 + 1200 = 8500
        # Equity: 6000 (credit)
        # Revenue: 0 + 2500 = 2500 (credit)
        # Total closing credits = 6000 + 2500 = 8500
        self.assertEqual(float(tb["total_closing_debits"]), 8500.00)
        self.assertEqual(float(tb["total_closing_credits"]), 8500.00)

        # 4. Retrieve Profit & Loss report
        res_pl = self.client.get("/api/v1/accounting/profit-loss", headers=self.headers_a)
        self.assertEqual(res_pl.status_code, 200)
        pl = res_pl.json()

        # Revenue = 2500, Expense = 1200, Profit = 1300
        self.assertEqual(float(pl["total_revenue"]), 2500.00)
        self.assertEqual(float(pl["total_expenses"]), 1200.00)
        self.assertEqual(float(pl["net_profit"]), 1300.00)

    def test_tenant_boundary_isolation(self):
        # Post JV in Tenant A
        payload = {
            "entry_date": str(date.today()),
            "description": "Tenant A JV",
            "lines": [
                {"account_id": str(self.cash_id), "amount": 100.00, "direction": "DEBIT"},
                {"account_id": str(self.equity_id), "amount": 100.00, "direction": "CREDIT"}
            ]
        }
        jv = self.client.post("/api/v1/accounting/journals", json=payload, headers=self.headers_a).json()

        # Attempt to access Tenant A's JV from Tenant B
        res_get = self.client.get(f"/api/v1/accounting/journals/{jv['id']}", headers=self.headers_b)
        self.assertEqual(res_get.status_code, 404)

        # Attempt to access Tenant A's ledger card from Tenant B
        res_led = self.client.get(f"/api/v1/accounting/ledger/{self.cash_id}", headers=self.headers_b)
        self.assertEqual(res_led.status_code, 404)

if __name__ == "__main__":
    unittest.main()
