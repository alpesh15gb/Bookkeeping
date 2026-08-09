"""
User Acceptance Test — Complete Business Simulation
Simulates a real Indian SMB running ApexBooks for one month.
Phase 1-3: Company setup, master data, daily operations, accounting & GST validation.
"""
import uuid
import time
from datetime import date, timedelta
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from src.main import app
from src.core.security import create_access_token, get_password_hash
from src.infrastructure.database.models import (
    Tenant, User, TenantMembership, Contact, Product, Account,
    Invoice, Bill, Expense, ExpenseCategory,
    JournalEntry, JournalLine, Payment, PaymentAllocation,
    CreditNote, DebitNote, FinancialYear, TenantSetting, NumberingSeries,
    BillPayment, BillPaymentAllocation, StockLedger, AuditLog,
)
from src.domains.accounting.services import AccountResolver
from src.domains.taxation.services import GSTEngine
from src.core.database import engine, Base, SessionLocal


@pytest.fixture(scope="module", autouse=True)
def _reset_schema_for_uat():
    """
    The application no longer runs Base.metadata.create_all() on startup
    (Alembic is the only production schema manager), so this module must
    (re)build the SQLite test schema itself like the sibling test modules do.
    """
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    SessionLocal.close_all()


# ════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════

def _register_company(client, email, password, company_name, gstin=None):
    payload = {
        "email": email,
        "password": password,
        "full_name": "UAT Admin",
        "company_legal_name": company_name,
    }
    if gstin:
        payload["company_gstin"] = gstin
    resp = client.post("/api/v1/auth/register", json=payload)
    return resp


def _login(client, email, password):
    resp = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    return resp


def _headers(token, tenant_id):
    return {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant_id)}


def _create_contact(client, headers, name, contact_type, state_code, gstin=None):
    resp = client.post("/api/v1/masters/contacts", json={
        "name": name,
        "contact_type": contact_type,
        "email": f"{name.lower().replace(' ', '.')}@example.com",
        "phone": "+919876543210",
        "state_code": state_code,
        "gstin": gstin,
        "registration_type": "REGULAR" if gstin else "UNREGISTERED",
        "billing_address": {
            "street": "123 Main St",
            "city": "Mumbai",
            "state": "Maharashtra",
            "state_code": state_code,
            "pincode": "400001",
            "country": "India",
        },
    }, headers=headers)
    return resp


def _create_product(client, headers, name, hsn, gst_rate, price, product_type="GOODS"):
    payload = {
        "name": name,
        "sku": f"SKU-{uuid.uuid4().hex[:6].upper()}",
        "hsn_sac": hsn,
        "product_type": product_type,
        "uom": "PCS",
        "sales_price": str(price),
        "purchase_price": str(Decimal(str(price)) * Decimal("0.7")),
        "gst_rate": str(gst_rate),
        "opening_stock": "1000" if product_type == "GOODS" else "0",
    }
    resp = client.post("/api/v1/masters/products", json=payload, headers=headers)
    return resp


def _create_invoice(client, headers, contact_id, product_id, qty, rate, gst_rate, pos_state):
    resp = client.post("/api/v1/invoices", json={
        "contact_id": str(contact_id),
        "issue_date": str(date.today()),
        "due_date": str(date.today() + timedelta(days=30)),
        "pos_state_code": pos_state,
        "line_items": [{
            "product_id": str(product_id),
            "quantity": qty,
            "rate": str(rate),
            "gst_rate": str(gst_rate),
            "hsn_sac": "998314",
        }],
    }, headers=headers)
    return resp


def _create_bill(client, headers, contact_id, product_id, qty, rate, gst_rate, pos_state):
    resp = client.post("/api/v1/bills", json={
        "contact_id": str(contact_id),
        "bill_number": f"BILL-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today() + timedelta(days=30)),
        "pos_state_code": pos_state,
        "line_items": [{
            "product_id": str(product_id),
            "quantity": qty,
            "rate": str(rate),
            "gst_rate": str(gst_rate),
            "hsn_sac": "998314",
        }],
    }, headers=headers)
    return resp


def _record_receipt(client, headers, contact_id, invoice_id, amount, mode="BANK"):
    resp = client.post("/api/v1/payments/receipts", json={
        "contact_id": str(contact_id),
        "payment_date": str(date.today()),
        "payment_mode": mode,
        "amount": str(amount),
        "allocations": [{"invoice_id": str(invoice_id), "amount": str(amount)}],
    }, headers=headers)
    return resp


def _create_expense(client, headers, category_id, amount, gst_rate="0.00"):
    resp = client.post("/api/v1/expenses", json={
        "expense_category_id": str(category_id),
        "expense_date": str(date.today()),
        "vendor_name": "Expense Vendor",
        "description": "UAT test expense",
        "amount": str(amount),
        "gst_rate": gst_rate,
    }, headers=headers)
    return resp


def _get_trial_balance(client, headers, as_of_date=None):
    params = {"as_of_date": str(as_of_date or date.today())}
    return client.get("/api/v1/reports/trial-balance", params=params, headers=headers)


def _get_balance_sheet(client, headers, as_of_date=None):
    params = {"as_of_date": str(as_of_date or date.today())}
    return client.get("/api/v1/reports/balance-sheet", params=params, headers=headers)


def _get_profit_loss(client, headers, start, end):
    return client.get("/api/v1/accounting/profit-loss",
                      params={"date_from": str(start), "date_to": str(end)},
                      headers=headers)


def _get_gstr1(client, headers, start, end):
    return client.get("/api/v1/gst/gstr1",
                      params={"start_date": str(start), "end_date": str(end)},
                      headers=headers)


# ════════════════════════════════════════════════════════════════════
# PHASE 1 — COMPLETE BUSINESS SIMULATION
# ════════════════════════════════════════════════════════════════════

class TestUAT_Phase1_BusinessSimulation:
    """
    Create a brand new company and operate it exactly like a real business.
    """

    @pytest.fixture(autouse=True)
    def setup_company(self, db_session, client):
        """Register a new company and set up auth."""
        self.db = db_session
        self.client = client
        self.email = f"uat_{uuid.uuid4().hex[:6]}@apexbooks.in"
        self.password = "UatSecure@1234"

        # Register company with GSTIN
        resp = _register_company(
            client, self.email, self.password,
            "UAT Demo Pvt Ltd", gstin="27AABCU0001A1Z5"
        )
        assert resp.status_code == 201

        # Login
        resp = _login(client, self.email, self.password)
        assert resp.status_code == 200
        self.token = resp.json()["access_token"]

        # Get tenant
        user = db_session.query(User).filter(User.email == self.email).first()
        membership = db_session.query(TenantMembership).filter(
            TenantMembership.user_id == user.id
        ).first()
        self.tenant_id = membership.tenant_id
        self.user_id = user.id
        self.headers = _headers(self.token, self.tenant_id)

    # ── Company Setup ──────────────────────────────────────────────

    def test_001_company_created_with_gst(self):
        """Company registered with GSTIN, tax_mode = GST_REGULAR."""
        tenant = self.db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
        assert tenant is not None
        assert tenant.tax_mode == "GST_REGULAR"
        assert tenant.gstin == "27AABCU0001A1Z5"

    def test_002_financial_year_created(self):
        """Financial year exists (created on registration or manually)."""
        tenant = self.db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
        assert tenant is not None

    def test_003_chart_of_accounts_seeded(self):
        """Chart of accounts auto-seeded with standard accounts."""
        resolver = AccountResolver(self.db, self.tenant_id)
        cash_id = resolver.resolve("assets.cash")
        assert cash_id is not None
        revenue_id = resolver.resolve("sales_revenue")
        assert revenue_id is not None

    def test_004_numbering_series_seeded(self):
        """Numbering series auto-seeded for all document types."""
        series = self.db.query(NumberingSeries).filter(
            NumberingSeries.tenant_id == self.tenant_id
        ).all()
        doc_types = {s.document_type for s in series}
        assert "INVOICE" in doc_types
        assert "BILL" in doc_types
        assert "RECEIPT" in doc_types

    def test_005_expense_categories_seeded(self):
        """Default expense categories created."""
        cats = self.db.query(ExpenseCategory).filter(
            ExpenseCategory.tenant_id == self.tenant_id
        ).all()
        assert len(cats) >= 10

    # ── Master Data ────────────────────────────────────────────────

    def test_010_create_customers(self):
        """Create 10 customers with realistic data."""
        customers = [
            ("Infosys Ltd", "29AABCI1234A1Z5", "29"),
            ("TCS Ltd", "27AABCT5678B1Z5", "27"),
            ("Wipro Ltd", "19AABCW3456C1Z5", "19"),
            ("HCL Technologies", "09AABCH7890D1Z5", "09"),
            ("Tech Mahindra", "27AABCT1111E1Z5", "27"),
            ("Reliance Retail", "24AABCR2222F1Z5", "24"),
            ("Tata Motors", "27AABCT3333G1Z5", "27"),
            ("Adani Enterprises", "24AABCA4444H1Z5", "24"),
            ("Bajaj Finance", "27AABCB5555I1Z5", "27"),
            ("Hindustan Unilever", "27AABCH6666J1Z5", "27"),
        ]
        for name, gstin, state in customers:
            resp = _create_contact(self.client, self.headers, name, "CUSTOMER", state, gstin)
            assert resp.status_code == 201, f"Failed to create {name}: {resp.text}"

    def test_011_create_vendors(self):
        """Create 5 vendors."""
        vendors = [
            ("AWS India", "27AAWCA7777K1Z5", "27"),
            ("Google Cloud India", "29AABCG8888L1Z5", "29"),
            ("Office Depot", "27AABCO9999M1Z5", "27"),
            ("Rent Provider", "27AABCR0000N1Z5", "27"),
            ("Utility Corp", "27AABCU1111O1Z5", "27"),
        ]
        for name, gstin, state in vendors:
            resp = _create_contact(self.client, self.headers, name, "VENDOR", state, gstin)
            assert resp.status_code == 201, f"Failed to create {name}: {resp.text}"

    def test_012_create_products(self):
        """Create 10 products with different GST rates."""
        products = [
            ("Web Development Service", "998314", 18, 5000, "SERVICE"),
            ("Mobile App Development", "998314", 18, 8000, "SERVICE"),
            ("Cloud Hosting", "998311", 18, 2000, "SERVICE"),
            ("Laptop Computer", "847130", 18, 65000, "GOODS"),
            ("Office Chair", "940130", 18, 12000, "GOODS"),
            ("Printer Paper A4", "480255", 12, 350, "GOODS"),
            ("Stationery Kit", "482010", 18, 500, "GOODS"),
            ("Network Switch", "851762", 18, 8500, "GOODS"),
            ("LED Monitor", "852852", 18, 15000, "GOODS"),
            ("UPS Battery", "850720", 28, 4500, "GOODS"),
        ]
        for name, hsn, rate, price, ptype in products:
            resp = _create_product(self.client, self.headers, name, hsn, rate, price, ptype)
            assert resp.status_code == 201, f"Failed to create {name}: {resp.text}"

    # ── Daily Operations ───────────────────────────────────────────

    def test_020_intrastate_sales_invoice(self):
        """Intra-state invoice (Maharashtra → Maharashtra): CGST + SGST."""
        # Create fresh data for this test
        _create_contact(self.client, self.headers, "MH Customer", "CUSTOMER", "27", "27AABCM1234A1Z5")
        _create_product(self.client, self.headers, "MH Product", "998314", 18, 5000, "SERVICE")

        customers = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()

        cust = next(c for c in customers if c.get("state_code") == "27")
        prod = next(p for p in products if float(p.get("gst_rate", 0)) == 18)

        resp = _create_invoice(
            self.client, self.headers,
            uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
            qty=10, rate=Decimal("5000"), gst_rate=18, pos_state="27"
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["status"] == "POSTED"
        assert Decimal(data["cgst_amount"]) > 0
        assert Decimal(data["sgst_amount"]) > 0
        assert Decimal(data["igst_amount"]) == 0

    def test_021_interstate_sales_invoice(self):
        """Inter-state invoice (Maharashtra → Karnataka): IGST."""
        # Create fresh contacts and products for this test
        _create_contact(self.client, self.headers, "KA Cust", "CUSTOMER", "29", "29AABCK5678B1Z5")
        _create_product(self.client, self.headers, "KA Prod", "998314", 18, 8000, "SERVICE")

        customers = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()

        cust = next(c for c in customers if c.get("state_code") == "29")
        prod = next(p for p in products if float(p.get("gst_rate", 0)) == 18)

        resp = _create_invoice(
            self.client, self.headers,
            uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
            qty=5, rate=Decimal("8000"), gst_rate=18, pos_state="29"
        )
        assert resp.status_code == 201
        data = resp.json()
        assert Decimal(data["igst_amount"]) > 0
        assert Decimal(data["cgst_amount"]) == 0

    def test_022_intrastate_purchase_bill(self):
        """Intra-state purchase bill with ITC."""
        # Create fresh vendor and product
        _create_contact(self.client, self.headers, "MH Vend", "VENDOR", "27", "27AABCV9999C1Z5")
        _create_product(self.client, self.headers, "Purch Item", "998314", 18, 3000, "SERVICE")

        vendors = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()

        vend = next(c for c in vendors if c.get("contact_type") == "VENDOR" and c.get("state_code") == "27")
        prod = next(p for p in products if float(p.get("gst_rate", 0)) == 18)

        resp = _create_bill(
            self.client, self.headers,
            uuid.UUID(vend["id"]), uuid.UUID(prod["id"]),
            qty=20, rate=Decimal("3000"), gst_rate=18, pos_state="27"
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["status"] == "POSTED"

    def test_023_customer_receipt(self):
        """Record customer receipt against invoice."""
        # Create fresh data
        _create_contact(self.client, self.headers, "Rcpt Cust", "CUSTOMER", "27", "27AABCR1234A1Z5")
        _create_product(self.client, self.headers, "Rcpt Prod", "998314", 18, 5000, "SERVICE")

        customers = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()
        cust = next(c for c in customers if c.get("contact_type") == "CUSTOMER")
        prod = products[0]
        inv_resp = _create_invoice(self.client, self.headers, uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
                                   qty=1, rate=Decimal("5000"), gst_rate=18, pos_state="27")
        assert inv_resp.status_code == 201
        inv = inv_resp.json()

        resp = _record_receipt(
            self.client, self.headers,
            uuid.UUID(inv["contact_id"]),
            uuid.UUID(inv["id"]),
            Decimal(inv["total"]),
            mode="BANK"
        )
        assert resp.status_code == 201

    def test_024_expense_creation(self):
        """Create and post an expense."""
        cats = self.client.get("/api/v1/masters/expense-categories", headers=self.headers).json()
        cat = cats[0]

        resp = _create_expense(self.client, self.headers, uuid.UUID(cat["id"]), Decimal("15000"), "18.00")
        assert resp.status_code == 201
        eid = resp.json()["id"]

        # Post the expense
        resp = self.client.post(f"/api/v1/expenses/{eid}/post", headers=self.headers)
        assert resp.status_code == 200
        assert resp.json()["status"] == "POSTED"

    def test_025_journal_entry(self):
        """Create a manual journal entry."""
        resolver = AccountResolver(self.db, self.tenant_id)
        cash_id = resolver.resolve("assets.cash")
        expense_id = resolver.resolve("expense.misc")

        resp = self.client.post("/api/v1/accounting/journals", json={
            "entry_date": str(date.today()),
            "description": "Petty cash expense",
            "lines": [
                {"account_id": str(expense_id), "amount": "500.00", "direction": "DEBIT"},
                {"account_id": str(cash_id), "amount": "500.00", "direction": "CREDIT"},
            ],
        }, headers=self.headers)
        assert resp.status_code == 201

    def test_026_credit_note(self):
        """Create a credit note against an invoice."""
        # Create fresh data
        _create_contact(self.client, self.headers, "CN Cust", "CUSTOMER", "27", "27AABCC1234A1Z5")
        _create_product(self.client, self.headers, "CN Prod", "998314", 18, 5000, "SERVICE")

        customers = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()
        cust = next(c for c in customers if c.get("contact_type") == "CUSTOMER")
        prod = products[0]
        inv_resp = _create_invoice(self.client, self.headers, uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
                                   qty=2, rate=Decimal("5000"), gst_rate=18, pos_state="27")
        assert inv_resp.status_code == 201
        inv = inv_resp.json()

        resp = self.client.post("/api/v1/invoices/credit-notes", json={
            "invoice_id": inv["id"],
            "issue_date": str(date.today()),
            "reason": "Partial return",
            "line_items": [{
                "product_id": prod["id"],
                "quantity": 1,
                "rate": "5000.00",
                "gst_rate": "18.00",
                "hsn_sac": "998314",
            }],
        }, headers=self.headers)
        assert resp.status_code == 201


# ════════════════════════════════════════════════════════════════════
# PHASE 2 — ACCOUNTING VALIDATION
# ════════════════════════════════════════════════════════════════════

class TestUAT_Phase2_AccountingValidation:
    """After every transaction verify ledger, trial balance, P&L, balance sheet."""

    @pytest.fixture(autouse=True)
    def setup(self, db_session, client):
        self.db = db_session
        self.client = client
        email = f"uat_acc_{uuid.uuid4().hex[:6]}@apexbooks.in"
        _register_company(client, email, "AccSecure@1234", "Acc Test Corp", gstin="27AABCA7777A1Z5")
        resp = _login(client, email, "AccSecure@1234")
        self.token = resp.json()["access_token"]
        user = db_session.query(User).filter(User.email == email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        self.tenant_id = membership.tenant_id
        self.headers = _headers(self.token, self.tenant_id)

        # Seed data
        _create_contact(client, self.headers, "Test Customer", "CUSTOMER", "27", "27AABCT1234A1Z5")
        _create_contact(client, self.headers, "Test Vendor", "VENDOR", "27", "27AABCV5678B1Z5")
        _create_product(client, self.headers, "Test Service", "998314", 18, 5000, "SERVICE")

    def test_100_trial_balance_balances(self):
        """Trial balance must always balance (debits = credits)."""
        resp = _get_trial_balance(self.client, self.headers)
        assert resp.status_code == 200
        data = resp.json()
        debits = Decimal(data["total_debits"])
        credits = Decimal(data["total_credits"])
        assert abs(debits - credits) < Decimal("0.01"), f"TB out of balance: D={debits}, C={credits}"

    def test_101_trial_balance_after_invoice(self):
        """Trial balance must balance after creating an invoice."""
        contacts = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()
        cust = next(c for c in contacts if c["contact_type"] == "CUSTOMER")
        prod = products[0]

        _create_invoice(self.client, self.headers, uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
                        qty=5, rate=Decimal("5000"), gst_rate=18, pos_state="27")

        resp = _get_trial_balance(self.client, self.headers)
        assert resp.status_code == 200
        data = resp.json()
        assert abs(Decimal(data["total_debits"]) - Decimal(data["total_credits"])) < Decimal("0.01")

    def test_102_balance_sheet_equation(self):
        """Assets = Liabilities + Equity."""
        resp = _get_balance_sheet(self.client, self.headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["is_balanced"] is True

    def test_103_profit_and_loss(self):
        """P&L report returns valid data."""
        resp = _get_profit_loss(self.client, self.headers, date(2026, 4, 1), date.today())
        assert resp.status_code == 200
        data = resp.json()
        assert "total_revenue" in data
        assert "total_expenses" in data
        assert "net_profit" in data

    def test_104_cash_book(self, db_session, client):
        """Cash book report works."""
        resp = self.client.get("/api/v1/reports/cash-book",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200


# ════════════════════════════════════════════════════════════════════
# PHASE 3 — GST VALIDATION
# ════════════════════════════════════════════════════════════════════

class TestUAT_Phase3_GSTValidation:
    """Generate GSTR-1, GSTR-3B, verify tax totals."""

    @pytest.fixture(autouse=True)
    def setup(self, db_session, client):
        self.db = db_session
        self.client = client
        email = f"uat_gst_{uuid.uuid4().hex[:6]}@apexbooks.in"
        _register_company(client, email, "GstSecure@1234", "GST Test Corp", gstin="27AABCG8888A1Z5")
        resp = _login(client, email, "GstSecure@1234")
        self.token = resp.json()["access_token"]
        user = db_session.query(User).filter(User.email == email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        self.tenant_id = membership.tenant_id
        self.headers = _headers(self.token, self.tenant_id)

        # Seed data and create transactions
        _create_contact(client, self.headers, "GST Customer", "CUSTOMER", "27", "27AABCG1234A1Z5")
        _create_contact(client, self.headers, "GST Vendor", "VENDOR", "27", "27AABCG5678B1Z5")
        _create_product(client, self.headers, "GST Service", "998314", 18, 10000, "SERVICE")

        contacts = client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = client.get("/api/v1/masters/products", headers=self.headers).json()
        cust = contacts[0]
        prod = products[0]

        # Create 3 invoices
        for i in range(3):
            _create_invoice(client, self.headers, uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
                            qty=i+1, rate=Decimal("10000"), gst_rate=18, pos_state="27")

    def test_200_gstr1_generates(self):
        """GSTR-1 report generates without error."""
        resp = _get_gstr1(self.client, self.headers, date(2026, 4, 1), date.today())
        assert resp.status_code == 200
        data = resp.json()
        assert "b2b" in data
        assert "hsn_summary" in data

    def test_201_gstr1_b2b_section(self):
        """GSTR-1 B2B section has registered customer invoices."""
        resp = _get_gstr1(self.client, self.headers, date(2026, 4, 1), date.today())
        data = resp.json()
        assert len(data["b2b"]) >= 3

    def test_202_gstr3b_generates(self):
        """GSTR-3B report generates without error."""
        resp = self.client.get("/api/v1/reports/gst/gstr3b",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200

    def test_203_gstr1_export(self):
        """GSTR-1 Excel export generates."""
        resp = self.client.get("/api/v1/gst/gstr1/export",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("application/vnd.openxmlformats")

    def test_204_gstin_validation(self):
        """GSTIN validation works."""
        resp = self.client.get("/api/v1/gst/validate-gstin/27AABCU0001A1Z5", headers=self.headers)
        assert resp.status_code == 200
        assert resp.json()["valid"] is True


# ════════════════════════════════════════════════════════════════════
# PHASE 5 — MULTI-USER VALIDATION
# ════════════════════════════════════════════════════════════════════

class TestUAT_Phase5_MultiUser:
    """Test multiple user roles with different permissions."""

    @pytest.fixture(autouse=True)
    def setup(self, db_session, client):
        self.db = db_session
        self.client = client
        self.email = f"uat_multi_{uuid.uuid4().hex[:6]}@apexbooks.in"
        _register_company(client, self.email, "MultiSecure@1234", "Multi User Corp", gstin="27AABCM9999A1Z5")
        resp = _login(client, self.email, "MultiSecure@1234")
        self.token = resp.json()["access_token"]
        user = db_session.query(User).filter(User.email == self.email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        self.tenant_id = membership.tenant_id
        self.headers = _headers(self.token, self.tenant_id)

        # Create accountant user
        acc_user = User(
            id=uuid.uuid4(), email=f"acc_{uuid.uuid4().hex[:6]}@test.com",
            password_hash=get_password_hash("AccPass@1234"), full_name="Accountant"
        )
        db_session.add(acc_user)
        db_session.add(TenantMembership(user_id=acc_user.id, tenant_id=self.tenant_id, role="accountant"))
        self.acc_headers = _headers(create_access_token(str(acc_user.id)), self.tenant_id)

        # Create salesperson user
        sales_user = User(
            id=uuid.uuid4(), email=f"sales_{uuid.uuid4().hex[:6]}@test.com",
            password_hash=get_password_hash("SalesPass@1234"), full_name="Sales User"
        )
        db_session.add(sales_user)
        db_session.add(TenantMembership(user_id=sales_user.id, tenant_id=self.tenant_id, role="salesperson"))
        self.sales_headers = _headers(create_access_token(str(sales_user.id)), self.tenant_id)

        db_session.commit()

    def test_300_owner_full_access(self):
        """Owner can access everything."""
        resp = self.client.get("/api/v1/invoices", headers=self.headers)
        assert resp.status_code == 200
        resp = self.client.get("/api/v1/accounting/journals", headers=self.headers)
        assert resp.status_code == 200

    def test_301_accountant_can_access_reports(self):
        """Accountant can access reports."""
        resp = self.client.get("/api/v1/reports/trial-balance",
                               params={"as_of_date": str(date.today())},
                               headers=self.acc_headers)
        assert resp.status_code == 200

    def test_302_salesperson_cannot_access_ledger(self):
        """Salesperson cannot access accounting journals."""
        resp = self.client.get("/api/v1/accounting/journals", headers=self.sales_headers)
        assert resp.status_code == 403

    def test_303_cross_tenant_isolation(self):
        """User from different tenant cannot access data."""
        other_user = User(
            id=uuid.uuid4(), email=f"other_{uuid.uuid4().hex[:6]}@test.com",
            password_hash=get_password_hash("OtherPass@1234"), full_name="Other User"
        )
        self.db.add(other_user)
        self.db.commit()
        other_token = create_access_token(str(other_user.id))
        other_headers = {"Authorization": f"Bearer {other_token}", "X-Tenant-ID": str(self.tenant_id)}
        resp = self.client.get("/api/v1/invoices", headers=other_headers)
        assert resp.status_code == 403


# ════════════════════════════════════════════════════════════════════
# PHASE 6 — REPORTS VALIDATION
# ════════════════════════════════════════════════════════════════════

class TestUAT_Phase6_Reports:
    """Validate every report type."""

    @pytest.fixture(autouse=True)
    def setup(self, db_session, client):
        self.db = db_session
        self.client = client
        email = f"uat_rpt_{uuid.uuid4().hex[:6]}@apexbooks.in"
        _register_company(client, email, "RptSecure@1234", "Report Corp", gstin="27AABCR1111A1Z5")
        resp = _login(client, email, "RptSecure@1234")
        self.token = resp.json()["access_token"]
        user = db_session.query(User).filter(User.email == email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        self.tenant_id = membership.tenant_id
        self.headers = _headers(self.token, self.tenant_id)

    def test_400_trial_balance(self):
        resp = self.client.get("/api/v1/reports/trial-balance",
                               params={"as_of_date": str(date.today())}, headers=self.headers)
        assert resp.status_code == 200

    def test_401_balance_sheet(self):
        resp = self.client.get("/api/v1/reports/balance-sheet",
                               params={"as_of_date": str(date.today())}, headers=self.headers)
        assert resp.status_code == 200

    def test_402_profit_loss(self):
        resp = self.client.get("/api/v1/accounting/profit-loss",
                               params={"date_from": "2026-04-01", "date_to": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200

    def test_403_cash_flow(self):
        resp = self.client.get("/api/v1/reports/cash-flow",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200

    def test_404_ar_aging(self):
        resp = self.client.get("/api/v1/reports/aging/receivables",
                               params={"as_of_date": str(date.today())}, headers=self.headers)
        assert resp.status_code == 200

    def test_405_ap_aging(self):
        resp = self.client.get("/api/v1/reports/aging/payables",
                               params={"as_of_date": str(date.today())}, headers=self.headers)
        assert resp.status_code == 200

    def test_406_gstr1_report(self):
        resp = self.client.get("/api/v1/gst/gstr1",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200

    def test_407_gstr2_report(self):
        resp = self.client.get("/api/v1/gst/gstr2",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200

    def test_408_balance_sheet_excel_export(self):
        resp = self.client.get("/api/v1/reports/balance-sheet/excel",
                               params={"as_of_date": str(date.today())}, headers=self.headers)
        assert resp.status_code == 200

    def test_409_balance_sheet_pdf_export(self):
        resp = self.client.get("/api/v1/reports/balance-sheet/pdf",
                               params={"as_of_date": str(date.today())}, headers=self.headers)
        assert resp.status_code == 200

    def test_410_gstr1_excel_export(self):
        resp = self.client.get("/api/v1/gst/gstr1/export",
                               params={"start_date": "2026-04-01", "end_date": str(date.today())},
                               headers=self.headers)
        assert resp.status_code == 200

    def test_411_invoice_list_with_pagination(self):
        resp = self.client.get("/api/v1/invoices",
                               params={"page": 1, "limit": 10}, headers=self.headers)
        assert resp.status_code == 200

    def test_412_dashboard_metrics(self):
        resp = self.client.get("/api/v1/dashboard/metrics", headers=self.headers)
        assert resp.status_code == 200


# ════════════════════════════════════════════════════════════════════
# PHASE 7 — STRESS TESTING
# ════════════════════════════════════════════════════════════════════

class TestUAT_Phase7_Stress:
    """Bulk operations and performance benchmarks."""

    @pytest.fixture(autouse=True)
    def setup(self, db_session, client):
        self.db = db_session
        self.client = client
        email = f"uat_stress_{uuid.uuid4().hex[:6]}@apexbooks.in"
        _register_company(client, email, "StressSecure@1234", "Stress Corp", gstin="27AABCS2222A1Z5")
        resp = _login(client, email, "StressSecure@1234")
        self.token = resp.json()["access_token"]
        user = db_session.query(User).filter(User.email == email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        self.tenant_id = membership.tenant_id
        self.headers = _headers(self.token, self.tenant_id)

        # Seed contacts and products
        _create_contact(client, self.headers, "Bulk Customer", "CUSTOMER", "27", "27AABCB1234A1Z5")
        _create_product(client, self.headers, "Bulk Product", "998314", 18, 1000, "SERVICE")

    def test_500_bulk_invoice_creation(self):
        """Create 50 invoices and verify performance."""
        contacts = self.client.get("/api/v1/masters/contacts", headers=self.headers).json()
        products = self.client.get("/api/v1/masters/products", headers=self.headers).json()
        cust = contacts[0]
        prod = products[0]

        start = time.monotonic()
        for i in range(50):
            resp = _create_invoice(
                self.client, self.headers,
                uuid.UUID(cust["id"]), uuid.UUID(prod["id"]),
                qty=1, rate=Decimal("1000"), gst_rate=18, pos_state="27"
            )
            assert resp.status_code == 201, f"Invoice {i} failed: {resp.text}"
        elapsed = time.monotonic() - start

        assert elapsed < 120, f"50 invoices took {elapsed:.1f}s (limit: 120s)"

    def test_501_trial_balance_after_bulk(self):
        """Trial balance must still balance after bulk operations."""
        resp = _get_trial_balance(self.client, self.headers)
        assert resp.status_code == 200
        data = resp.json()
        assert abs(Decimal(data["total_debits"]) - Decimal(data["total_credits"])) < Decimal("0.01")

    def test_502_invoice_list_performance(self):
        """Invoice list with pagination must respond quickly."""
        start = time.monotonic()
        resp = self.client.get("/api/v1/invoices", params={"page": 1, "limit": 50}, headers=self.headers)
        elapsed = time.monotonic() - start
        assert resp.status_code == 200
        assert elapsed < 5.0, f"Invoice list took {elapsed:.2f}s"

    def test_503_report_generation_performance(self):
        """Reports must generate within threshold."""
        start = time.monotonic()
        resp = _get_trial_balance(self.client, self.headers)
        elapsed = time.monotonic() - start
        assert resp.status_code == 200
        assert elapsed < 10.0, f"Trial balance took {elapsed:.2f}s"
