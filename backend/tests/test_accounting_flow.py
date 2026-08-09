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
from src.infrastructure.database.models import (
    Account,
    JournalEntry,
    TenantMembership,
    User,
)


class TestAccountingFlow(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        self.client.post(
            "/api/v1/auth/register",
            json={
                "email": "owner_a@company.com",
                "password": "SecurePassword123!",
                "full_name": "Vijay Varma A",
                "phone_number": "+919999988881",
                "company_legal_name": "Tenant A Pvt Ltd",
                "company_gstin": "27AAAAA1111A1Z1",
                "company_pan": "AAAAA1111A",
            },
        )
        login_a = self.client.post(
            "/api/v1/auth/login",
            json={"email": "owner_a@company.com", "password": "SecurePassword123!"},
        ).json()
        self.token_a = login_a["access_token"]

        self.client.post(
            "/api/v1/auth/register",
            json={
                "email": "owner_b@company.com",
                "password": "SecurePassword123!",
                "full_name": "Vijay Varma B",
                "phone_number": "+919999988882",
                "company_legal_name": "Tenant B Pvt Ltd",
                "company_gstin": "27BBBBB2222B2Z2",
                "company_pan": "BBBBB2222B",
            },
        )
        login_b = self.client.post(
            "/api/v1/auth/login",
            json={"email": "owner_b@company.com", "password": "SecurePassword123!"},
        ).json()
        self.token_b = login_b["access_token"]

        db = SessionLocal()
        try:
            user_a = db.query(User).filter(User.email == "owner_a@company.com").first()
            user_b = db.query(User).filter(User.email == "owner_b@company.com").first()
            self.tenant_a_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user_a.id
            ).first().tenant_id
            self.tenant_b_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user_b.id
            ).first().tenant_id

            accounts = [
                Account(
                    tenant_id=self.tenant_a_id,
                    name="Cash A/c",
                    code="10001",
                    account_type="ASSET",
                    opening_balance=Decimal("1000.00"),
                    current_balance=Decimal("1000.00"),
                    is_active=True,
                ),
                Account(
                    tenant_id=self.tenant_a_id,
                    name="Bank A/c",
                    code="10002",
                    account_type="ASSET",
                    opening_balance=Decimal("5000.00"),
                    current_balance=Decimal("5000.00"),
                    is_active=True,
                ),
                Account(
                    tenant_id=self.tenant_a_id,
                    name="Sales Revenue",
                    code="30001",
                    account_type="REVENUE",
                    opening_balance=Decimal("0.00"),
                    current_balance=Decimal("0.00"),
                    is_active=True,
                ),
                Account(
                    tenant_id=self.tenant_a_id,
                    name="Rent Expense",
                    code="40001",
                    account_type="EXPENSE",
                    opening_balance=Decimal("0.00"),
                    current_balance=Decimal("0.00"),
                    is_active=True,
                ),
                Account(
                    tenant_id=self.tenant_a_id,
                    name="Owner Equity",
                    code="20001",
                    account_type="EQUITY",
                    opening_balance=Decimal("6000.00"),
                    current_balance=Decimal("6000.00"),
                    is_active=True,
                ),
            ]
            db.add_all(accounts)
            db.commit()
            for account in accounts:
                db.refresh(account)
            self.cash_id = accounts[0].id
            self.bank_id = accounts[1].id
            self.revenue_id = accounts[2].id
            self.rent_id = accounts[3].id
            self.equity_id = accounts[4].id
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

    def _post_journal(self, description, debit_id, credit_id, amount):
        return self.client.post(
            "/api/v1/accounting/journals",
            json={
                "entry_date": str(date.today()),
                "description": description,
                "lines": [
                    {
                        "account_id": str(debit_id),
                        "amount": float(amount),
                        "direction": "DEBIT",
                    },
                    {
                        "account_id": str(credit_id),
                        "amount": float(amount),
                        "direction": "CREDIT",
                    },
                ],
            },
            headers=self.headers_a,
        )

    def test_journal_creation_and_balance_verification(self):
        created = self._post_journal(
            "Office rent payment", self.rent_id, self.bank_id, Decimal("1200.00")
        )
        self.assertEqual(created.status_code, 201, created.text)
        journal = created.json()
        self.assertTrue(journal["reference_number"].startswith("JV/"))
        self.assertEqual(len(journal["lines"]), 2)

        db = SessionLocal()
        try:
            self.assertEqual(db.get(Account, self.rent_id).current_balance, Decimal("1200.0000"))
            self.assertEqual(db.get(Account, self.bank_id).current_balance, Decimal("3800.0000"))
        finally:
            db.close()

        # The public correction contract is DELETE. It creates an immutable
        # reversal rather than exposing a separate /reverse workflow.
        deleted = self.client.delete(
            f"/api/v1/accounting/journals/{journal['id']}", headers=self.headers_a
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)

        db = SessionLocal()
        try:
            original = db.get(JournalEntry, uuid.UUID(journal["id"]))
            self.assertIsNotNone(original)
            reversal = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.source_type == "JOURNAL_REVERSAL",
                JournalEntry.source_id == original.id,
            ).one()
            self.assertIsNotNone(reversal)
            self.assertEqual(db.get(Account, self.rent_id).current_balance, Decimal("0.0000"))
            self.assertEqual(db.get(Account, self.bank_id).current_balance, Decimal("5000.0000"))
        finally:
            db.close()

        duplicate_delete = self.client.delete(
            f"/api/v1/accounting/journals/{journal['id']}", headers=self.headers_a
        )
        self.assertEqual(duplicate_delete.status_code, 409)

        unbalanced = self.client.post(
            "/api/v1/accounting/journals",
            json={
                "entry_date": str(date.today()),
                "description": "Unbalanced entry",
                "lines": [
                    {"account_id": str(self.rent_id), "amount": 1000.00, "direction": "DEBIT"},
                    {"account_id": str(self.bank_id), "amount": 800.00, "direction": "CREDIT"},
                ],
            },
            headers=self.headers_a,
        )
        self.assertEqual(unbalanced.status_code, 400)

        single = self.client.post(
            "/api/v1/accounting/journals",
            json={
                "entry_date": str(date.today()),
                "description": "Single line entry",
                "lines": [
                    {"account_id": str(self.rent_id), "amount": 1000.00, "direction": "DEBIT"}
                ],
            },
            headers=self.headers_a,
        )
        self.assertEqual(single.status_code, 400)

    def test_ledger_running_balance(self):
        created = self._post_journal(
            "Rent payment", self.rent_id, self.bank_id, Decimal("1200.00")
        )
        self.assertEqual(created.status_code, 201)
        response = self.client.get(
            f"/api/v1/accounting/ledger/{self.bank_id}", headers=self.headers_a
        )
        self.assertEqual(response.status_code, 200)
        report = response.json()
        self.assertEqual(float(report["opening_balance"]), 5000.00)
        self.assertEqual(len(report["lines"]), 1)
        self.assertEqual(float(report["lines"][0]["credit_amount"]), 1200.00)
        self.assertEqual(float(report["closing_balance"]), 3800.00)

    def test_trial_balance_and_profit_loss(self):
        self.assertEqual(
            self._post_journal("Rent", self.rent_id, self.bank_id, Decimal("1200.00")).status_code,
            201,
        )
        self.assertEqual(
            self._post_journal(
                "Consultancy sales", self.cash_id, self.revenue_id, Decimal("2500.00")
            ).status_code,
            201,
        )

        tb_response = self.client.get("/api/v1/accounting/trial-balance", headers=self.headers_a)
        self.assertEqual(tb_response.status_code, 200)
        tb = tb_response.json()
        self.assertEqual(float(tb["total_opening_debits"]), 6000.00)
        self.assertEqual(float(tb["total_opening_credits"]), 6000.00)
        self.assertEqual(float(tb["total_debits"]), 3700.00)
        self.assertEqual(float(tb["total_credits"]), 3700.00)
        self.assertEqual(float(tb["total_closing_debits"]), 8500.00)
        self.assertEqual(float(tb["total_closing_credits"]), 8500.00)

        pl_response = self.client.get("/api/v1/accounting/profit-loss", headers=self.headers_a)
        self.assertEqual(pl_response.status_code, 200)
        pl = pl_response.json()
        self.assertEqual(float(pl["total_revenue"]), 2500.00)
        self.assertEqual(float(pl["total_expenses"]), 1200.00)
        self.assertEqual(float(pl["net_profit"]), 1300.00)

    def test_tenant_boundary_isolation(self):
        created = self._post_journal(
            "Tenant A JV", self.cash_id, self.equity_id, Decimal("100.00")
        )
        self.assertEqual(created.status_code, 201)
        journal = created.json()

        inaccessible = self.client.get(
            f"/api/v1/accounting/journals/{journal['id']}", headers=self.headers_b
        )
        self.assertEqual(inaccessible.status_code, 404)
        ledger = self.client.get(
            f"/api/v1/accounting/ledger/{self.cash_id}", headers=self.headers_b
        )
        self.assertEqual(ledger.status_code, 404)


if __name__ == "__main__":
    unittest.main()
