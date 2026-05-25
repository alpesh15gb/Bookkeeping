"""
Module 9 Tests — Reports & Analytics
Tests cover: Balance Sheet, GSTR-1, GSTR-3B, AR/AP Aging, Cash Flow,
             Sales Analytics, Purchase Analytics, Outstanding AR/AP.

All tests use an in-memory SQLite database (shared test engine from src.core.database).
Uses the register → login → seed pattern consistent with existing test modules.
"""
import sys
import os
import uuid
import unittest
from decimal import Decimal
from datetime import date, timedelta
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product,
    Invoice, InvoiceLine, Bill, BillLine,
    Account, JournalEntry, JournalLine
)


class TestReports(unittest.TestCase):
    """
    Comprehensive test suite for Module 9: Reports & Analytics.
    """

    # ----------------------------------------------------------------
    # Setup / Teardown
    # ----------------------------------------------------------------

    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # Register Tenant A (owner)
        self.client.post("/api/v1/auth/register", json={
            "email": "owner_a@reports.com",
            "password": "Pwd12345!",
            "full_name": "Report Owner A",
            "phone_number": "+919876543210",
            "company_legal_name": "Alpha Reports Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A",
        })
        login_a = self.client.post("/api/v1/auth/login", json={
            "email": "owner_a@reports.com",
            "password": "Pwd12345!",
        }).json()
        self.token_a = login_a["access_token"]

        # Register Tenant B (isolated tenant)
        self.client.post("/api/v1/auth/register", json={
            "email": "owner_b@reports.com",
            "password": "Pwd12345!",
            "full_name": "Report Owner B",
            "phone_number": "+919876543211",
            "company_legal_name": "Beta Reports Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z2",
            "company_pan": "BBBBB2222B",
        })
        login_b = self.client.post("/api/v1/auth/login", json={
            "email": "owner_b@reports.com",
            "password": "Pwd12345!",
        }).json()
        self.token_b = login_b["access_token"]

        # Retrieve tenant IDs from membership table
        db = SessionLocal()
        try:
            user_a = db.query(User).filter(User.email == "owner_a@reports.com").first()
            mem_a = db.query(TenantMembership).filter(TenantMembership.user_id == user_a.id).first()
            self.tenant_a = mem_a.tenant_id

            user_b = db.query(User).filter(User.email == "owner_b@reports.com").first()
            mem_b = db.query(TenantMembership).filter(TenantMembership.user_id == user_b.id).first()
            self.tenant_b = mem_b.tenant_id

            # Seed contacts
            self.customer = Contact(
                id=uuid.UUID("aaaa0001-0000-0000-0000-000000000001"),
                tenant_id=self.tenant_a,
                name="TCS Ltd",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                registration_type="REGULAR",
                billing_address={"city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001"},
                state_code="27",
            )
            self.vendor = Contact(
                id=uuid.UUID("aaaa0002-0000-0000-0000-000000000002"),
                tenant_id=self.tenant_a,
                name="Infosys Ltd",
                contact_type="VENDOR",
                gstin="29AAACI5678B2Z2",
                registration_type="REGULAR",
                billing_address={"city": "Bengaluru", "state": "Karnataka", "state_code": "29", "pincode": "560100"},
                state_code="29",
            )
            db.add_all([self.customer, self.vendor])

            # Seed accounts
            self.acct_asset = Account(
                id=uuid.UUID("ffff0001-0000-0000-0000-000000000001"),
                tenant_id=self.tenant_a, name="Bank Account", code="1001",
                account_type="ASSET", opening_balance=Decimal("100000.00"),
                current_balance=Decimal("100000.00"),
            )
            self.acct_rev = Account(
                id=uuid.UUID("ffff0002-0000-0000-0000-000000000002"),
                tenant_id=self.tenant_a, name="Sales Revenue", code="4001",
                account_type="REVENUE", opening_balance=Decimal("0.00"),
                current_balance=Decimal("0.00"),
            )
            self.acct_exp = Account(
                id=uuid.UUID("ffff0003-0000-0000-0000-000000000003"),
                tenant_id=self.tenant_a, name="COGS", code="5001",
                account_type="EXPENSE", opening_balance=Decimal("0.00"),
                current_balance=Decimal("0.00"),
            )
            self.acct_equity = Account(
                id=uuid.UUID("ffff0004-0000-0000-0000-000000000004"),
                tenant_id=self.tenant_a, name="Owner Capital", code="3001",
                account_type="EQUITY", opening_balance=Decimal("500000.00"),
                current_balance=Decimal("500000.00"),
            )
            self.acct_liab = Account(
                id=uuid.UUID("ffff0005-0000-0000-0000-000000000005"),
                tenant_id=self.tenant_a, name="Loan Payable", code="2001",
                account_type="LIABILITY", opening_balance=Decimal("200000.00"),
                current_balance=Decimal("200000.00"),
            )
            db.add_all([self.acct_asset, self.acct_rev, self.acct_exp, self.acct_equity, self.acct_liab])

            # Invoice 1: INV-001 — SENT, 118000 total, 50000 paid, INTRA-STATE (CGST+SGST)
            # Issue: 2025-04-15, Due: 2025-05-15
            inv1 = Invoice(
                id=uuid.UUID("dddd0001-0000-0000-0000-000000000001"),
                tenant_id=self.tenant_a,
                contact_id=self.customer.id,
                invoice_number="INV-001",
                issue_date=date(2025, 4, 15), due_date=date(2025, 5, 15),
                status="SENT",
                subtotal=Decimal("100000.00"), discount_total=Decimal("0.00"),
                cgst_amount=Decimal("9000.00"), sgst_amount=Decimal("9000.00"),
                igst_amount=Decimal("0.00"), utgst_amount=Decimal("0.00"),
                cess_amount=Decimal("0.00"), round_off=Decimal("0.00"),
                total=Decimal("118000.00"), amount_paid=Decimal("50000.00"),
                pos_state_code="27",
            )
            il1 = InvoiceLine(
                invoice_id=inv1.id,
                quantity=Decimal("1.0000"), rate=Decimal("100000.0000"),
                discount=Decimal("0.0000"), subtotal=Decimal("100000.0000"),
                hsn_sac="84713010", gst_rate=Decimal("18.00"),
                cgst_rate=Decimal("9.00"), cgst_amount=Decimal("9000.0000"),
                sgst_rate=Decimal("9.00"), sgst_amount=Decimal("9000.0000"),
                igst_rate=Decimal("0.00"), igst_amount=Decimal("0.0000"),
                utgst_rate=Decimal("0.00"), utgst_amount=Decimal("0.0000"),
                cess_rate=Decimal("0.00"), cess_amount=Decimal("0.0000"),
                total=Decimal("118000.0000"),
            )
            db.add(inv1)
            db.add(il1)

            # Invoice 2: INV-002 — PAID, nil-rated, 50000 total
            # Issue: 2025-05-10, Due: 2025-06-10
            inv2 = Invoice(
                id=uuid.UUID("dddd0002-0000-0000-0000-000000000002"),
                tenant_id=self.tenant_a,
                contact_id=self.customer.id,
                invoice_number="INV-002",
                issue_date=date(2025, 5, 10), due_date=date(2025, 6, 10),
                status="PAID",
                subtotal=Decimal("50000.00"), discount_total=Decimal("0.00"),
                cgst_amount=Decimal("0.00"), sgst_amount=Decimal("0.00"),
                igst_amount=Decimal("0.00"), utgst_amount=Decimal("0.00"),
                cess_amount=Decimal("0.00"), round_off=Decimal("0.00"),
                total=Decimal("50000.00"), amount_paid=Decimal("50000.00"),
                pos_state_code="29",
            )
            il2 = InvoiceLine(
                invoice_id=inv2.id,
                quantity=Decimal("10.0000"), rate=Decimal("5000.0000"),
                discount=Decimal("0.0000"), subtotal=Decimal("50000.0000"),
                hsn_sac="998313", gst_rate=Decimal("0.00"),
                cgst_rate=Decimal("0.00"), cgst_amount=Decimal("0.0000"),
                sgst_rate=Decimal("0.00"), sgst_amount=Decimal("0.0000"),
                igst_rate=Decimal("0.00"), igst_amount=Decimal("0.0000"),
                utgst_rate=Decimal("0.00"), utgst_amount=Decimal("0.0000"),
                cess_rate=Decimal("0.00"), cess_amount=Decimal("0.0000"),
                total=Decimal("50000.0000"),
            )
            db.add(inv2)
            db.add(il2)

            # Bill 1: BILL-001 — UNPAID, 35400 total
            # Issue: 2025-04-20, Due: 2025-05-20
            bill1 = Bill(
                id=uuid.UUID("eeee0001-0000-0000-0000-000000000001"),
                tenant_id=self.tenant_a,
                contact_id=self.vendor.id,
                bill_number="BILL-001",
                issue_date=date(2025, 4, 20), due_date=date(2025, 5, 20),
                status="UNPAID",
                subtotal=Decimal("30000.00"), discount_total=Decimal("0.00"),
                cgst_amount=Decimal("2700.00"), sgst_amount=Decimal("2700.00"),
                igst_amount=Decimal("0.00"), utgst_amount=Decimal("0.00"),
                cess_amount=Decimal("0.00"),
                total=Decimal("35400.00"), amount_paid=Decimal("0.00"),
                pos_state_code="27",
            )
            bl1 = BillLine(
                bill_id=bill1.id,
                quantity=Decimal("1.0000"), rate=Decimal("30000.0000"),
                discount=Decimal("0.0000"), subtotal=Decimal("30000.0000"),
                hsn_sac="94031000", gst_rate=Decimal("18.00"),
                cgst_rate=Decimal("9.00"), cgst_amount=Decimal("2700.0000"),
                sgst_rate=Decimal("9.00"), sgst_amount=Decimal("2700.0000"),
                igst_rate=Decimal("0.00"), igst_amount=Decimal("0.0000"),
                utgst_rate=Decimal("0.00"), utgst_amount=Decimal("0.0000"),
                cess_rate=Decimal("0.00"), cess_amount=Decimal("0.0000"),
                total=Decimal("35400.0000"),
            )
            db.add(bill1)
            db.add(bl1)

            # Journal entries for P&L and Cash Flow tests
            # JE-001: Invoice 001 posting (DR Bank, CR Revenue)
            je1 = JournalEntry(
                id=uuid.uuid4(), tenant_id=self.tenant_a,
                entry_date=date(2025, 4, 15), reference_number="JE-001",
                description="INV-001 posting", source_type="INVOICE",
            )
            db.add(je1)
            db.flush()
            db.add(JournalLine(entry_id=je1.id, account_id=self.acct_asset.id,
                               amount=Decimal("118000.00"), direction="DEBIT"))
            db.add(JournalLine(entry_id=je1.id, account_id=self.acct_rev.id,
                               amount=Decimal("118000.00"), direction="CREDIT"))

            # JE-002: Invoice 002 posting (DR Bank, CR Revenue)
            je2 = JournalEntry(
                id=uuid.uuid4(), tenant_id=self.tenant_a,
                entry_date=date(2025, 5, 10), reference_number="JE-002",
                description="INV-002 posting", source_type="INVOICE",
            )
            db.add(je2)
            db.flush()
            db.add(JournalLine(entry_id=je2.id, account_id=self.acct_asset.id,
                               amount=Decimal("50000.00"), direction="DEBIT"))
            db.add(JournalLine(entry_id=je2.id, account_id=self.acct_rev.id,
                               amount=Decimal("50000.00"), direction="CREDIT"))

            # JE-003: Bill 001 posting (DR COGS, CR Liability)
            je3 = JournalEntry(
                id=uuid.uuid4(), tenant_id=self.tenant_a,
                entry_date=date(2025, 4, 20), reference_number="JE-003",
                description="BILL-001 posting", source_type="BILL",
            )
            db.add(je3)
            db.flush()
            db.add(JournalLine(entry_id=je3.id, account_id=self.acct_exp.id,
                               amount=Decimal("35400.00"), direction="DEBIT"))
            db.add(JournalLine(entry_id=je3.id, account_id=self.acct_liab.id,
                               amount=Decimal("35400.00"), direction="CREDIT"))

            db.commit()

            self.customer_id = self.customer.id
            self.vendor_id = self.vendor.id
        finally:
            db.close()

        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a),
            "Authorization": f"Bearer {self.token_a}",
        }
        self.headers_b = {
            "X-Tenant-ID": str(self.tenant_b),
            "Authorization": f"Bearer {self.token_b}",
        }
        # Report date constants
        self.as_of = "2025-06-30"
        self.start = "2025-04-01"
        self.end = "2025-06-30"

    # ----------------------------------------------------------------
    # Balance Sheet
    # ----------------------------------------------------------------

    def test_balance_sheet_returns_200(self):
        resp = self.client.get("/api/v1/reports/balance-sheet",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("assets", data)
        self.assertIn("liabilities", data)
        self.assertIn("equity", data)
        self.assertIn("is_balanced", data)

    def test_balance_sheet_assets_include_bank(self):
        resp = self.client.get("/api/v1/reports/balance-sheet",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        asset_names = [i["account_name"] for i in data["assets"]["items"]]
        self.assertIn("Bank Account", asset_names)
        # Bank account: opening 100000 + JE debit 118000 + 50000 = 268000
        assets_total = Decimal(str(data["assets"]["total"]))
        self.assertEqual(assets_total, Decimal("268000.00"))

    def test_balance_sheet_equity_includes_current_year_earnings(self):
        resp = self.client.get("/api/v1/reports/balance-sheet",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        eq_names = [i["account_name"] for i in data["equity"]["items"]]
        self.assertTrue(any("Current Year Earnings" in n for n in eq_names))

    def test_balance_sheet_tenant_b_empty(self):
        resp = self.client.get("/api/v1/reports/balance-sheet",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_b)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["assets"]["items"], [])
        self.assertEqual(data["liabilities"]["items"], [])

    # ----------------------------------------------------------------
    # GSTR-1
    # ----------------------------------------------------------------

    def test_gstr1_b2b_registered_customer(self):
        resp = self.client.get("/api/v1/reports/gst/gstr1",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        # Both invoices go to B2B (TCS has GSTIN)
        self.assertGreaterEqual(len(data["b2b"]), 1)
        b2b = data["b2b"][0]
        self.assertEqual(b2b["receiver_gstin"], "27AAACT1234A1Z1")
        self.assertEqual(b2b["invoice_count"], 2)
        # Total taxable = 100000 + 50000
        self.assertEqual(Decimal(str(b2b["taxable_value"])), Decimal("150000.00"))

    def test_gstr1_totals(self):
        resp = self.client.get("/api/v1/reports/gst/gstr1",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_taxable_value"])), Decimal("150000.00"))
        self.assertEqual(Decimal(str(data["total_cgst"])), Decimal("9000.00"))
        self.assertEqual(Decimal(str(data["total_invoice_value"])), Decimal("168000.00"))

    def test_gstr1_hsn_summary_has_both_codes(self):
        resp = self.client.get("/api/v1/reports/gst/gstr1",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        hsn_codes = [h["hsn_sac"] for h in data["hsn_summary"]]
        self.assertIn("84713010", hsn_codes)
        self.assertIn("998313", hsn_codes)

    def test_gstr1_empty_period(self):
        resp = self.client.get("/api/v1/reports/gst/gstr1",
                               params={"start_date": "2024-01-01", "end_date": "2024-01-31"},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["b2b"], [])
        self.assertEqual(Decimal(str(data["total_taxable_value"])), Decimal("0.00"))

    def test_gstr1_tenant_b_sees_nothing(self):
        resp = self.client.get("/api/v1/reports/gst/gstr1",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_b)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["b2b"], [])
        self.assertEqual(Decimal(str(data["total_taxable_value"])), Decimal("0.00"))

    # ----------------------------------------------------------------
    # GSTR-3B
    # ----------------------------------------------------------------

    def test_gstr3b_outward_supplies(self):
        resp = self.client.get("/api/v1/reports/gst/gstr3b",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        out = data["outward_taxable_supplies"]
        # Only INV-001 is taxable (18% GST); INV-002 is nil rated
        self.assertEqual(Decimal(str(out["taxable_value"])), Decimal("100000.00"))
        self.assertEqual(Decimal(str(out["central_tax"])), Decimal("9000.00"))
        self.assertEqual(Decimal(str(out["state_ut_tax"])), Decimal("9000.00"))

    def test_gstr3b_nil_rated_supplies(self):
        resp = self.client.get("/api/v1/reports/gst/gstr3b",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        nil = data["nil_rated_supplies"]
        self.assertEqual(Decimal(str(nil["taxable_value"])), Decimal("50000.00"))

    def test_gstr3b_itc_from_bills(self):
        resp = self.client.get("/api/v1/reports/gst/gstr3b",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        itc = data["inward_supplies_itc"]
        self.assertEqual(Decimal(str(itc["central_tax"])), Decimal("2700.00"))
        self.assertEqual(Decimal(str(itc["state_ut_tax"])), Decimal("2700.00"))

    def test_gstr3b_net_tax_payable(self):
        resp = self.client.get("/api/v1/reports/gst/gstr3b",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        # Output CGST 9000 - ITC CGST 2700 = 6300 net payable
        self.assertEqual(Decimal(str(data["net_tax_payable_cgst"])), Decimal("6300.00"))
        self.assertEqual(Decimal(str(data["net_tax_payable_sgst"])), Decimal("6300.00"))
        self.assertEqual(Decimal(str(data["net_tax_payable_igst"])), Decimal("0.00"))

    # ----------------------------------------------------------------
    # AR Aging
    # ----------------------------------------------------------------

    def test_ar_aging_outstanding_amount(self):
        """INV-001 SENT: total 118000, paid 50000 → 68000 outstanding."""
        resp = self.client.get("/api/v1/reports/aging/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["report_type"], "RECEIVABLES")
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("68000.00"))
        self.assertEqual(len(data["lines"]), 1)
        self.assertEqual(data["lines"][0]["contact_name"], "TCS Ltd")

    def test_ar_aging_correct_bucket_46_days_overdue(self):
        """INV-001 due 2025-05-15, as_of 2025-06-30 → 46 days overdue → 31-60 bucket."""
        resp = self.client.get("/api/v1/reports/aging/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        buckets = {b["label"]: Decimal(str(b["amount"])) for b in data["lines"][0]["buckets"]}
        self.assertEqual(buckets["31-60 days"], Decimal("68000.00"))
        self.assertEqual(buckets["0-30 days"], Decimal("0.00"))

    def test_ar_aging_paid_invoice_excluded(self):
        """INV-002 PAID → should not appear in AR aging."""
        resp = self.client.get("/api/v1/reports/aging/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        # Only INV-001 is outstanding
        self.assertEqual(len(data["lines"]), 1)

    def test_ar_aging_bucket_totals_sum_to_grand_total(self):
        resp = self.client.get("/api/v1/reports/aging/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        bucket_sum = sum(Decimal(str(b["amount"])) for b in data["bucket_totals"])
        self.assertEqual(bucket_sum, Decimal(str(data["total_outstanding"])))

    def test_ar_aging_tenant_b_empty(self):
        resp = self.client.get("/api/v1/reports/aging/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_b)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("0.00"))
        self.assertEqual(data["lines"], [])

    # ----------------------------------------------------------------
    # AP Aging
    # ----------------------------------------------------------------

    def test_ap_aging_outstanding_bill(self):
        """BILL-001 UNPAID: total 35400, due 2025-05-20, as_of 2025-06-30 → 41 days overdue."""
        resp = self.client.get("/api/v1/reports/aging/payables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["report_type"], "PAYABLES")
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("35400.00"))
        self.assertEqual(len(data["lines"]), 1)
        self.assertEqual(data["lines"][0]["contact_name"], "Infosys Ltd")

    def test_ap_aging_bucket_41_days(self):
        """41 days overdue → 31-60 days bucket."""
        resp = self.client.get("/api/v1/reports/aging/payables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        buckets = {b["label"]: Decimal(str(b["amount"])) for b in data["lines"][0]["buckets"]}
        self.assertEqual(buckets["31-60 days"], Decimal("35400.00"))
        self.assertEqual(buckets["0-30 days"], Decimal("0.00"))

    # ----------------------------------------------------------------
    # Cash Flow
    # ----------------------------------------------------------------

    def test_cash_flow_structure(self):
        resp = self.client.get("/api/v1/reports/cash-flow",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        for key in ["operating_activities", "investing_activities", "financing_activities",
                    "net_change_in_cash", "opening_cash_balance", "closing_cash_balance"]:
            self.assertIn(key, data)

    def test_cash_flow_net_profit_in_operating(self):
        """Net profit from journals: Revenue credits 168000, Expense debits 35400 → 132600."""
        resp = self.client.get("/api/v1/reports/cash-flow",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        op_items = {item["label"]: Decimal(str(item["amount"])) for item in data["operating_activities"]["items"]}
        self.assertIn("Net Profit / (Loss)", op_items)
        self.assertEqual(op_items["Net Profit / (Loss)"], Decimal("132600.00"))

    def test_cash_flow_closing_balance_equation(self):
        """closing = opening + net_change."""
        resp = self.client.get("/api/v1/reports/cash-flow",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        opening = Decimal(str(data["opening_cash_balance"]))
        net = Decimal(str(data["net_change_in_cash"]))
        closing = Decimal(str(data["closing_cash_balance"]))
        self.assertEqual(closing, opening + net)

    # ----------------------------------------------------------------
    # Sales Analytics
    # ----------------------------------------------------------------

    def test_sales_analytics_totals(self):
        resp = self.client.get("/api/v1/reports/analytics/sales",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        # Both invoices: subtotals 100000 + 50000
        self.assertEqual(Decimal(str(data["total_sales"])), Decimal("150000.00"))
        self.assertEqual(data["invoice_count"], 2)
        # Tax: 9000 CGST + 9000 SGST = 18000 (only from INV-001; INV-002 nil)
        self.assertEqual(Decimal(str(data["total_tax_collected"])), Decimal("18000.00"))
        self.assertEqual(Decimal(str(data["total_invoiced"])), Decimal("168000.00"))

    def test_sales_analytics_top_customer(self):
        resp = self.client.get("/api/v1/reports/analytics/sales",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        self.assertEqual(len(data["top_customers"]), 1)
        cust = data["top_customers"][0]
        self.assertEqual(cust["contact_name"], "TCS Ltd")
        self.assertEqual(cust["invoice_count"], 2)
        self.assertEqual(Decimal(str(cust["total_invoiced"])), Decimal("168000.00"))

    def test_sales_analytics_tenant_b_empty(self):
        resp = self.client.get("/api/v1/reports/analytics/sales",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_b)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["invoice_count"], 0)
        self.assertEqual(Decimal(str(data["total_invoiced"])), Decimal("0.00"))

    def test_sales_analytics_top_n_limit(self):
        resp = self.client.get("/api/v1/reports/analytics/sales",
                               params={"start_date": self.start, "end_date": self.end, "top_n": "1"},
                               headers=self.headers_a)
        data = resp.json()
        self.assertLessEqual(len(data["top_customers"]), 1)

    # ----------------------------------------------------------------
    # Purchase Analytics
    # ----------------------------------------------------------------

    def test_purchase_analytics_totals(self):
        resp = self.client.get("/api/v1/reports/analytics/purchases",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_purchases"])), Decimal("30000.00"))
        self.assertEqual(Decimal(str(data["total_tax_paid"])), Decimal("5400.00"))
        self.assertEqual(Decimal(str(data["total_billed"])), Decimal("35400.00"))
        self.assertEqual(data["bill_count"], 1)

    def test_purchase_analytics_top_vendor(self):
        resp = self.client.get("/api/v1/reports/analytics/purchases",
                               params={"start_date": self.start, "end_date": self.end},
                               headers=self.headers_a)
        data = resp.json()
        self.assertEqual(len(data["top_vendors"]), 1)
        vendor = data["top_vendors"][0]
        self.assertEqual(vendor["contact_name"], "Infosys Ltd")
        self.assertEqual(vendor["bill_count"], 1)

    # ----------------------------------------------------------------
    # Outstanding AR
    # ----------------------------------------------------------------

    def test_outstanding_ar_correct_amount(self):
        """INV-001 total 118000, paid 50000 → outstanding 68000, 46 days overdue."""
        resp = self.client.get("/api/v1/reports/outstanding/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("68000.00"))
        self.assertEqual(len(data["invoices"]), 1)
        inv = data["invoices"][0]
        self.assertEqual(inv["invoice_number"], "INV-001")
        self.assertEqual(Decimal(str(inv["outstanding"])), Decimal("68000.00"))
        self.assertEqual(inv["days_overdue"], 46)

    def test_outstanding_ar_paid_excluded(self):
        """INV-002 PAID → should NOT appear."""
        resp = self.client.get("/api/v1/reports/outstanding/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        data = resp.json()
        inv_numbers = [i["invoice_number"] for i in data["invoices"]]
        self.assertNotIn("INV-002", inv_numbers)

    def test_outstanding_ar_tenant_b_empty(self):
        resp = self.client.get("/api/v1/reports/outstanding/receivables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_b)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("0.00"))
        self.assertEqual(data["invoices"], [])

    # ----------------------------------------------------------------
    # Outstanding AP
    # ----------------------------------------------------------------

    def test_outstanding_ap_correct_amount(self):
        """BILL-001 total 35400, unpaid → 35400 outstanding, 41 days overdue."""
        resp = self.client.get("/api/v1/reports/outstanding/payables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_a)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("35400.00"))
        self.assertEqual(len(data["bills"]), 1)
        bill = data["bills"][0]
        self.assertEqual(bill["bill_number"], "BILL-001")
        self.assertEqual(Decimal(str(bill["outstanding"])), Decimal("35400.00"))
        self.assertEqual(bill["days_overdue"], 41)

    def test_outstanding_ap_tenant_b_empty(self):
        resp = self.client.get("/api/v1/reports/outstanding/payables",
                               params={"as_of_date": self.as_of},
                               headers=self.headers_b)
        data = resp.json()
        self.assertEqual(Decimal(str(data["total_outstanding"])), Decimal("0.00"))
        self.assertEqual(data["bills"], [])

    # ----------------------------------------------------------------
    # RBAC: Salesperson denied access to reports
    # ----------------------------------------------------------------

    def test_salesperson_cannot_access_reports(self):
        """Salesperson role does not have reports:view permission."""
        # Register salesperson under Tenant A
        self.client.post("/api/v1/auth/register", json={
            "email": "sp@reports.com",
            "password": "Pwd12345!",
            "full_name": "Sales Person",
            "phone_number": "+919876543212",
            "company_legal_name": "SP Company",
            "company_gstin": "27CCCCC3333C3Z3",
            "company_pan": "CCCCC3333C",
        })

        # Update membership to salesperson role
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == "sp@reports.com").first()
            mem = db.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
            mem.role = "salesperson"
            db.commit()
            sp_tenant = mem.tenant_id
        finally:
            db.close()

        login = self.client.post("/api/v1/auth/login", json={
            "email": "sp@reports.com", "password": "Pwd12345!",
        }).json()
        sp_token = login["access_token"]
        sp_headers = {"Authorization": f"Bearer {sp_token}", "X-Tenant-ID": str(sp_tenant)}

        resp = self.client.get("/api/v1/reports/outstanding/receivables",
                               params={"as_of_date": self.as_of},
                               headers=sp_headers)
        self.assertEqual(resp.status_code, 403)

    # ----------------------------------------------------------------
    # Auditor CAN access reports
    # ----------------------------------------------------------------

    def test_auditor_can_access_reports(self):
        """Auditor role has reports:view permission."""
        self.client.post("/api/v1/auth/register", json={
            "email": "auditor@reports.com",
            "password": "Pwd12345!",
            "full_name": "Auditor",
            "phone_number": "+919876543213",
            "company_legal_name": "Auditor Company",
            "company_gstin": "27DDDDD4444D4Z4",
            "company_pan": "DDDDD4444D",
        })
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == "auditor@reports.com").first()
            mem = db.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
            mem.role = "auditor"
            db.commit()
            aud_tenant = mem.tenant_id
        finally:
            db.close()

        login = self.client.post("/api/v1/auth/login", json={
            "email": "auditor@reports.com", "password": "Pwd12345!",
        }).json()
        aud_token = login["access_token"]
        aud_headers = {"Authorization": f"Bearer {aud_token}", "X-Tenant-ID": str(aud_tenant)}

        resp = self.client.get("/api/v1/reports/outstanding/receivables",
                               params={"as_of_date": self.as_of},
                               headers=aud_headers)
        # Auditor is in their own tenant with no invoices — but 200 is expected
        self.assertEqual(resp.status_code, 200)


if __name__ == "__main__":
    unittest.main()
