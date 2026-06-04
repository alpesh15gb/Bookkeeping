import sys
import os
import uuid
import unittest
from datetime import date, timedelta
from decimal import Decimal
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import User, Tenant, TenantMembership, Account, JournalEntry, JournalLine, AccountingPeriod

class TestYearEndFlow(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # Register Tenant
        reg_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma",
            "phone_number": "+919999988881",
            "company_legal_name": "Apex Books Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A"
        }
        self.client.post("/api/v1/auth/register", json=reg_payload)
        login = self.client.post("/api/v1/auth/login", json={
            "email": "owner@company.com",
            "password": "SecurePassword123!"
        }).json()
        self.token = login["access_token"]

        db = SessionLocal()
        try:
            m = db.query(TenantMembership).filter(
                TenantMembership.user_id == db.query(User).filter(User.email == "owner@company.com").first().id
            ).first()
            self.tenant_id = m.tenant_id

            # Set financial year start in db
            tenant = db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
            tenant.financial_year_start = date(2025, 4, 1)

            # Resolve/Seed accounts
            from src.domains.accounting.services import AccountResolver
            resolver = AccountResolver(db, self.tenant_id)
            self.cash_id = resolver.resolve("assets.cash")
            self.revenue_id = resolver.resolve("sales_revenue")
            self.rent_id = resolver.resolve("expense.rent")
            self.retained_id = resolver.resolve("equity.retained")

            db.commit()
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.token}"
        }

    def test_year_end_flow(self):
        # 1. Post transactions in the FY period:
        # Sales Revenue: 5000 (credit) -> Cash: 5000 (debit)
        payload_sale = {
            "entry_date": "2026-03-15",
            "description": "Sales",
            "lines": [
                {"account_id": str(self.cash_id), "amount": 5000.00, "direction": "DEBIT"},
                {"account_id": str(self.revenue_id), "amount": 5000.00, "direction": "CREDIT"}
            ]
        }
        res = self.client.post("/api/v1/accounting/journals", json=payload_sale, headers=self.headers)
        self.assertEqual(res.status_code, 201)

        # Rent Expense: 2000 (debit) -> Cash: 2000 (credit)
        payload_rent = {
            "entry_date": "2026-03-20",
            "description": "Rent",
            "lines": [
                {"account_id": str(self.rent_id), "amount": 2000.00, "direction": "DEBIT"},
                {"account_id": str(self.cash_id), "amount": 2000.00, "direction": "CREDIT"}
            ]
        }
        res2 = self.client.post("/api/v1/accounting/journals", json=payload_rent, headers=self.headers)
        self.assertEqual(res2.status_code, 201)

        # 2. Check year end prepare endpoint
        res_prep = self.client.get("/api/v1/accounting/year-end/prepare?closing_date=2026-03-31", headers=self.headers)
        self.assertEqual(res_prep.status_code, 200)
        prep = res_prep.json()
        self.assertTrue(prep["ready"])
        self.assertTrue(prep["trial_balance_balanced"])
        self.assertEqual(float(prep["net_profit"]), 3000.00) # 5000 - 2000

        # 3. Perform Year End Close
        res_close = self.client.post("/api/v1/accounting/year-end/close", json={"closing_date": "2026-03-31"}, headers=self.headers)
        self.assertEqual(res_close.status_code, 200)

        # 4. Verify Accounting Period is marked closed
        db = SessionLocal()
        try:
            period = db.query(AccountingPeriod).filter(
                AccountingPeriod.tenant_id == self.tenant_id,
                AccountingPeriod.period_name == "FY 2025-26"
            ).first()
            self.assertIsNotNone(period)
            self.assertTrue(period.is_closed)

            # Verify Tenant financial year start has updated to April 1st, 2026
            tenant = db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
            self.assertEqual(tenant.financial_year_start, date(2026, 4, 1))
        finally:
            db.close()

        # 5. Verify Period Lock: posting to a closed period fails
        payload_locked = {
            "entry_date": "2026-03-25",
            "description": "Late entry",
            "lines": [
                {"account_id": str(self.cash_id), "amount": 500.00, "direction": "DEBIT"},
                {"account_id": str(self.revenue_id), "amount": 500.00, "direction": "CREDIT"}
            ]
        }
        res_locked = self.client.post("/api/v1/accounting/journals", json=payload_locked, headers=self.headers)
        self.assertEqual(res_locked.status_code, 422)
        self.assertIn("closed accounting period", res_locked.json()["detail"])

if __name__ == "__main__":
    unittest.main()
