"""
Backend Integration Sprint — Comprehensive Validation Suite
Covers P1-P7: Critical Blockers, API Contracts, Accounting Engine,
GST Validation, Offline Sync, Performance, Security.
"""
import uuid
import time
import json
from datetime import date, timedelta, datetime, timezone
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from src.main import app
from src.core.security import create_access_token, get_password_hash
from src.infrastructure.database.models import (
    Tenant, User, TenantMembership, Contact, Product, Account,
    Invoice, InvoiceLine, Bill, BillLine, Expense, ExpenseCategory,
    JournalEntry, JournalLine, Payment, PaymentAllocation,
    CreditNote, CreditNoteLine, DebitNote, DebitNoteLine,
    FinancialYear, AccountingPeriod, TenantSetting, NumberingSeries,
    BankingProfile, StockLedger, AuditLog,
)
from src.domains.accounting.services import AccountResolver
from src.domains.taxation.services import GSTEngine


# ──────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────

def _seed_tenant(db, gstin="27AAPFU0939F1ZV", tax_mode="GST_REGULAR"):
    tenant = Tenant(
        id=uuid.uuid4(),
        legal_name="Sprint Test Corp",
        trade_name="SprintTest",
        gstin=gstin,
        pan="AAPFU0939F",
        tax_mode=tax_mode,
        financial_year_start=date(2026, 4, 1),
    )
    db.add(tenant)
    db.flush()

    setting = TenantSetting(
        tenant_id=tenant.id,
        currency="INR",
        origin_state_code=gstin[:2] if gstin else None,
        gst_enabled=(tax_mode != "NON_GST"),
    )
    db.add(setting)

    fy = FinancialYear(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="2026-27",
        start_date=date(2026, 4, 1),
        end_date=date(2027, 3, 31),
        status="CURRENT",
        is_current=True,
        transaction_count=0,
        created_by=tenant.id,
    )
    db.add(fy)
    db.commit()
    return tenant


def _seed_user(db, tenant, email="sprint@test.com", role="owner"):
    user = User(
        id=uuid.uuid4(),
        email=email,
        password_hash=get_password_hash("Test@1234"),
        full_name="Sprint Tester",
    )
    db.add(user)
    membership = TenantMembership(
        user_id=user.id,
        tenant_id=tenant.id,
        role=role,
        is_active=True,
    )
    db.add(membership)
    db.commit()
    return user


def _auth(user, tenant):
    token = create_access_token(user_id=str(user.id))
    return {
        "Authorization": f"Bearer {token}",
        "X-Tenant-ID": str(tenant.id),
    }


def _seed_contact(db, tenant, name="Acme Corp", gstin="29AAACB1234F1Z5", state_code="29", contact_type="CUSTOMER"):
    contact = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name=name,
        email=f"{name.lower().replace(' ', '')}@test.com",
        phone="+919876543210",
        contact_type=contact_type,
        gstin=gstin,
        registration_type="REGULAR",
        billing_address={"street": "1 St", "city": "Bengaluru", "state": "Karnataka", "state_code": state_code, "pincode": "560001", "country": "India"},
        state_code=state_code,
        is_active=True,
    )
    db.add(contact)
    db.commit()
    return contact


def _seed_product(db, tenant, name="Web Service", gst_rate=Decimal("18.00"), hsn="998314"):
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name=name,
        sku="WS-001",
        hsn_sac=hsn,
        product_type="SERVICE",
        uom="PCS",
        sales_price=Decimal("5000.00"),
        purchase_price=Decimal("3000.00"),
        gst_rate=gst_rate,
        opening_stock=Decimal("0"),
        current_stock=Decimal("0"),
        is_active=True,
    )
    db.add(product)
    db.commit()
    return product


def _seed_expense_category(db, tenant):
    resolver = AccountResolver(db, tenant.id)
    account_id = resolver.resolve("expense.misc")
    cat = ExpenseCategory(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Miscellaneous",
        linked_account_id=account_id,
        is_active=True,
    )
    db.add(cat)
    db.commit()
    return cat


def _seed_numbering_series(db, tenant):
    for doc_type in ["INVOICE", "BILL", "JOURNAL", "EXPENSE", "PAYMENT", "CREDIT_NOTE", "DEBIT_NOTE"]:
        ns = NumberingSeries(
            id=uuid.uuid4(),
            tenant_id=tenant.id,
            document_type=doc_type,
            prefix=f"{doc_type[:3]}-",
            next_number=1,
            padding_digits=4,
            is_active=True,
        )
        db.add(ns)
    db.commit()


def _make_invoice_payload(contact_id, product_id, qty=2, rate="5000.00", pos_state="29"):
    return {
        "contact_id": str(contact_id),
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": pos_state,
        "line_items": [
            {
                "product_id": str(product_id),
                "quantity": qty,
                "rate": rate,
                "gst_rate": "18.00",
                "hsn_sac": "998314",
            }
        ],
    }


# ──────────────────────────────────────────────────────────────────────
# P1 — Critical Blockers
# ──────────────────────────────────────────────────────────────────────

class TestP1_CriticalBlockers:
    """B-01: GST calculation discrepancies
    B-02: Reports returning HTTP 422
    B-03: Financial Year lock enforcement
    """

    def test_b01_gst_registration_auto_detects_tax_mode(self, db_session, client):
        """B-01: Registration with GSTIN must auto-set tax_mode to GST_REGULAR."""
        email = f"b01_{uuid.uuid4().hex[:6]}@test.com"
        resp = client.post("/api/v1/auth/register", json={
            "email": email,
            "password": "StrongP@ss1",
            "full_name": "B01 User",
            "company_legal_name": "B01 Corp",
            "company_gstin": "27AABCT1234R1Z5",
        })
        assert resp.status_code == 201
        user = db_session.query(User).filter(User.email == email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        tenant = db_session.query(Tenant).filter(Tenant.id == membership.tenant_id).first()
        assert tenant.tax_mode == "GST_REGULAR"

    def test_b01_gst_registration_without_gstin_is_non_gst(self, db_session, client):
        """B-01: Registration without GSTIN must set tax_mode to NON_GST."""
        email = f"b01n_{uuid.uuid4().hex[:6]}@test.com"
        resp = client.post("/api/v1/auth/register", json={
            "email": email,
            "password": "StrongP@ss1",
            "full_name": "B01 NoGST",
            "company_legal_name": "B01 NoGST Corp",
        })
        assert resp.status_code == 201
        user = db_session.query(User).filter(User.email == email).first()
        membership = db_session.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        tenant = db_session.query(Tenant).filter(Tenant.id == membership.tenant_id).first()
        assert tenant.tax_mode == "NON_GST"

    def test_b01_intrastate_invoice_cgst_sgst(self, db_session, client):
        """B-01: Intra-state invoice must split into CGST + SGST."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 201
        data = resp.json()
        subtotal = Decimal(data["subtotal"])
        cgst = Decimal(data["cgst_amount"])
        sgst = Decimal(data["sgst_amount"])
        igst = Decimal(data["igst_amount"])
        expected_tax = subtotal * Decimal("0.18")
        assert cgst + sgst == pytest.approx(float(expected_tax), abs=1.0)
        assert igst == 0
        assert cgst == pytest.approx(float(expected_tax / 2), abs=1.0)
        assert sgst == pytest.approx(float(expected_tax / 2), abs=1.0)

    def test_b01_interstate_invoice_igst(self, db_session, client):
        """B-01: Inter-state invoice must use IGST."""
        tenant = _seed_tenant(db_session, gstin="27AAPFU0939F1ZV")
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="29AAACB1234F1Z5", state_code="29")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, pos_state="29")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 201
        data = resp.json()
        subtotal = Decimal(data["subtotal"])
        igst = Decimal(data["igst_amount"])
        cgst = Decimal(data["cgst_amount"])
        sgst = Decimal(data["sgst_amount"])
        expected_tax = subtotal * Decimal("0.18")
        assert igst == pytest.approx(float(expected_tax), abs=1.0)
        assert cgst == 0
        assert sgst == 0

    def test_b02_trial_balance_returns_200(self, db_session, client):
        """B-02: Trial balance report must return 200, not 422."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get("/api/v1/reports/trial-balance", params={"as_of_date": str(date.today())}, headers=headers)
        assert resp.status_code == 200

    def test_b02_balance_sheet_returns_200(self, db_session, client):
        """B-02: Balance sheet must return 200."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get("/api/v1/reports/balance-sheet", params={"as_of_date": str(date.today())}, headers=headers)
        assert resp.status_code == 200

    def test_b02_profit_loss_returns_200(self, db_session, client):
        """B-02: P&L must return 200."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get(
            "/api/v1/accounting/profit-loss",
            params={"date_from": "2026-04-01", "date_to": "2027-03-31"},
            headers=headers,
        )
        assert resp.status_code == 200

    def test_b02_gstr1_returns_200(self, db_session, client):
        """B-02: GSTR-1 must return 200 (was returning 500 in production)."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get(
            "/api/v1/gst/gstr1",
            params={"start_date": "2026-04-01", "end_date": "2027-03-31"},
            headers=headers,
        )
        assert resp.status_code == 200

    def test_b03_locked_fy_rejects_posting(self, db_session, client):
        """B-03: Posting to a locked FY must return 422."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        fy = db_session.query(FinancialYear).filter(
            FinancialYear.tenant_id == tenant.id
        ).first()
        fy.status = "LOCKED"
        db_session.commit()

        contact = _seed_contact(db_session, tenant)
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        payload = _make_invoice_payload(contact.id, product.id)
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 422

    def test_b03_closed_period_rejects_posting(self, db_session, client):
        """B-03: Posting to a closed accounting period must return 422."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        period = AccountingPeriod(
            id=uuid.uuid4(),
            tenant_id=tenant.id,
            period_name="Apr 2026",
            start_date=date(2026, 4, 1),
            end_date=date(2026, 4, 30),
            is_closed=True,
        )
        db_session.add(period)
        db_session.commit()

        contact = _seed_contact(db_session, tenant)
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        payload = _make_invoice_payload(contact.id, product.id)
        payload["issue_date"] = "2026-04-15"
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 422


# ──────────────────────────────────────────────────────────────────────
# P2 — API Contract Validation
# ──────────────────────────────────────────────────────────────────────

class TestP2_APIContractValidation:

    def test_auth_missing_credentials_returns_422(self, client):
        resp = client.post("/api/v1/auth/login", json={})
        assert resp.status_code == 422

    def test_auth_invalid_password_returns_401(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        resp = client.post("/api/v1/auth/login", json={
            "email": user.email,
            "password": "WrongPassword1!",
        })
        assert resp.status_code == 401

    def test_missing_auth_token_returns_401(self, client):
        resp = client.get("/api/v1/invoices", headers={"X-Tenant-ID": str(uuid.uuid4())})
        assert resp.status_code == 401

    def test_missing_tenant_header_returns_400(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        token = create_access_token(user_id=str(user.id))
        resp = client.get("/api/v1/invoices", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 400

    def test_cross_tenant_access_denied(self, db_session, client):
        tenant1 = _seed_tenant(db_session)
        tenant2 = _seed_tenant(db_session, gstin="29BBBCT5678R1Z6")
        user1 = _seed_user(db_session, tenant1)
        headers = _auth(user1, tenant2)
        resp = client.get("/api/v1/invoices", headers=headers)
        assert resp.status_code == 403

    def test_contacts_crud(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        # Create
        resp = client.post("/api/v1/masters/contacts", json={
            "name": "API Test Contact",
            "contact_type": "CUSTOMER",
            "email": "apitest@test.com",
            "phone": "+919876543210",
            "state_code": "27",
            "billing_address": {"street": "1 St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
        }, headers=headers)
        assert resp.status_code == 201
        cid = resp.json()["id"]

        # Get
        resp = client.get(f"/api/v1/masters/contacts/{cid}", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["name"] == "API Test Contact"

        # List
        resp = client.get("/api/v1/masters/contacts", headers=headers)
        assert resp.status_code == 200
        assert len(resp.json()) >= 1

        # Update
        resp = client.put(f"/api/v1/masters/contacts/{cid}", json={
            "name": "Updated Contact",
        }, headers=headers)
        assert resp.status_code == 200
        assert resp.json()["name"] == "Updated Contact"

        # Delete
        resp = client.delete(f"/api/v1/masters/contacts/{cid}", headers=headers)
        assert resp.status_code == 204

    def test_products_crud(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.post("/api/v1/masters/products", json={
            "name": "API Test Product",
            "sku": "ATP-001",
            "hsn_sac": "998314",
            "product_type": "SERVICE",
            "uom": "PCS",
            "sales_price": "1000.00",
            "purchase_price": "600.00",
            "gst_rate": "18.00",
        }, headers=headers)
        assert resp.status_code == 201
        pid = resp.json()["id"]

        resp = client.get(f"/api/v1/masters/products/{pid}", headers=headers)
        assert resp.status_code == 200

        resp = client.get("/api/v1/masters/products", headers=headers)
        assert resp.status_code == 200

        resp = client.delete(f"/api/v1/masters/products/{pid}", headers=headers)
        assert resp.status_code == 204

    def test_invoice_validation_bad_contact_returns_404(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(uuid.uuid4(), product.id)
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 404

    def test_invoice_validation_bad_product_returns_400(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, uuid.uuid4())
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 400

    def test_invoice_pagination(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get("/api/v1/invoices", params={"page": 1, "limit": 10}, headers=headers)
        assert resp.status_code == 200

    def test_expense_preview_returns_200(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.post("/api/v1/expenses/preview", json={
            "amount": "1000.00",
            "gst_rate": "18.00",
        }, headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "total" in data
        assert "cgst_amount" in data

    def test_expense_crud_lifecycle(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        cat = _seed_expense_category(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        # Create
        resp = client.post("/api/v1/expenses", json={
            "expense_category_id": str(cat.id),
            "expense_date": str(date.today()),
            "vendor_name": "Test Vendor",
            "description": "Sprint test expense",
            "amount": "1000.00",
            "gst_rate": "18.00",
        }, headers=headers)
        assert resp.status_code == 201
        eid = resp.json()["id"]
        assert resp.json()["status"] == "DRAFT"

        # Get
        resp = client.get(f"/api/v1/expenses/{eid}", headers=headers)
        assert resp.status_code == 200

        # List
        resp = client.get("/api/v1/expenses", headers=headers)
        assert resp.status_code == 200

        # Delete draft
        resp = client.delete(f"/api/v1/expenses/{eid}", headers=headers)
        assert resp.status_code == 204

    def test_financial_years_list(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get("/api/v1/financial-years", headers=headers)
        assert resp.status_code == 200
        assert isinstance(resp.json(), list)

    def test_dashboard_returns_200(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get("/api/v1/dashboard/metrics", headers=headers)
        assert resp.status_code == 200


# ──────────────────────────────────────────────────────────────────────
# P3 — Accounting Engine Validation
# ──────────────────────────────────────────────────────────────────────

class TestP3_AccountingEngine:

    def _setup(self, db):
        tenant = _seed_tenant(db)
        user = _seed_user(db, tenant)
        contact = _seed_contact(db, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db, tenant)
        _seed_numbering_series(db, tenant)
        return tenant, user, contact, product

    def test_invoice_auto_posts_to_ledger(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _auth(user, tenant)
        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 201
        data = resp.json()
        assert data["status"] == "POSTED"

        journals = db_session.query(JournalEntry).filter(
            JournalEntry.tenant_id == tenant.id,
            JournalEntry.source_type == "INVOICE",
        ).all()
        assert len(journals) >= 1
        lines = db_session.query(JournalLine).filter(
            JournalLine.entry_id == journals[0].id
        ).all()
        debits = sum(l.amount for l in lines if l.direction == "DEBIT")
        credits = sum(l.amount for l in lines if l.direction == "CREDIT")
        assert debits == pytest.approx(credits, abs=Decimal("0.01"))

    def test_trial_balance_balances_after_invoice(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _auth(user, tenant)
        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        client.post("/api/v1/invoices", json=payload, headers=headers)

        resp = client.get(
            "/api/v1/reports/trial-balance",
            params={"as_of_date": str(date.today())},
            headers=headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        total_debits = Decimal(data["total_debits"])
        total_credits = Decimal(data["total_credits"])
        assert abs(total_debits - total_credits) < Decimal("0.01")

    def test_balance_sheet_equation(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _auth(user, tenant)
        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        client.post("/api/v1/invoices", json=payload, headers=headers)

        resp = client.get(
            "/api/v1/reports/balance-sheet",
            params={"as_of_date": str(date.today())},
            headers=headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["is_balanced"] is True

    def test_bill_auto_posts(self, db_session, client):
        tenant, user, _, _ = self._setup(db_session)
        vendor = _seed_contact(db_session, tenant, name="Vendor Co", gstin="27AAACV9999F1Z5", state_code="27", contact_type="VENDOR")
        product = _seed_product(db_session, tenant, name="Purchase Item")
        headers = _auth(user, tenant)

        resp = client.post("/api/v1/bills", json={
            "contact_id": str(vendor.id),
            "bill_number": f"BILL-{uuid.uuid4().hex[:8].upper()}",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": str(product.id),
                "quantity": 1,
                "rate": "3000.00",
                "gst_rate": "18.00",
                "hsn_sac": "998314",
            }],
        }, headers=headers)
        assert resp.status_code in (200, 201)

    def test_expense_posting_creates_journal(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        cat = _seed_expense_category(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.post("/api/v1/expenses", json={
            "expense_category_id": str(cat.id),
            "expense_date": str(date.today()),
            "vendor_name": "Expense Vendor",
            "description": "Test expense",
            "amount": "500.00",
            "gst_rate": "0.00",
        }, headers=headers)
        assert resp.status_code == 201
        eid = resp.json()["id"]

        resp = client.post(f"/api/v1/expenses/{eid}/post", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["status"] == "POSTED"

    def test_manual_journal_entry(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        resolver = AccountResolver(db_session, tenant.id)
        cash_id = resolver.resolve("assets.cash")
        revenue_id = resolver.resolve("sales_revenue")

        resp = client.post("/api/v1/accounting/journals", json={
            "entry_date": str(date.today()),
            "description": "Manual test journal",
            "lines": [
                {"account_id": str(cash_id), "amount": "1000.00", "direction": "DEBIT"},
                {"account_id": str(revenue_id), "amount": "1000.00", "direction": "CREDIT"},
            ],
        }, headers=headers)
        assert resp.status_code == 201
        data = resp.json()
        assert len(data["lines"]) == 2

    def test_unbalanced_journal_rejected(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        resolver = AccountResolver(db_session, tenant.id)
        cash_id = resolver.resolve("assets.cash")
        revenue_id = resolver.resolve("sales_revenue")

        resp = client.post("/api/v1/accounting/journals", json={
            "entry_date": str(date.today()),
            "description": "Unbalanced",
            "lines": [
                {"account_id": str(cash_id), "amount": "1000.00", "direction": "DEBIT"},
                {"account_id": str(revenue_id), "amount": "500.00", "direction": "CREDIT"},
            ],
        }, headers=headers)
        assert resp.status_code == 400

    def test_payment_creates_posting(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 201
        inv_id = resp.json()["id"]
        inv_total = resp.json()["total"]

        resp = client.post(f"/api/v1/invoices/{inv_id}/payment", json={
            "contact_id": str(contact.id),
            "amount": inv_total,
            "payment_date": str(date.today()),
            "payment_mode": "CASH",
        }, headers=headers)
        assert resp.status_code in (200, 201)

    def test_invoice_cancel_creates_reversal(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _auth(user, tenant)
        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        inv_id = resp.json()["id"]

        resp = client.post(f"/api/v1/invoices/{inv_id}/cancel", headers=headers)
        assert resp.status_code == 200

        journals = db_session.query(JournalEntry).filter(
            JournalEntry.tenant_id == tenant.id,
        ).all()
        assert len(journals) >= 2


# ──────────────────────────────────────────────────────────────────────
# P4 — GST Validation
# ──────────────────────────────────────────────────────────────────────

class TestP4_GSTValidation:

    def test_gst_engine_intrastate(self):
        split = GSTEngine.calculate_tax(
            origin_state_code="27",
            place_of_supply_state_code="27",
            base_amount=Decimal("100000"),
            gst_rate=Decimal("18"),
        )
        assert split.cgst_amount + split.sgst_amount == pytest.approx(18000, abs=1)
        assert split.igst_amount == 0

    def test_gst_engine_interstate(self):
        split = GSTEngine.calculate_tax(
            origin_state_code="27",
            place_of_supply_state_code="29",
            base_amount=Decimal("100000"),
            gst_rate=Decimal("18"),
        )
        assert split.igst_amount == pytest.approx(18000, abs=1)
        assert split.cgst_amount == 0
        assert split.sgst_amount == 0

    def test_gst_engine_cess(self):
        split = GSTEngine.calculate_tax(
            origin_state_code="27",
            place_of_supply_state_code="27",
            base_amount=Decimal("100000"),
            gst_rate=Decimal("18"),
            cess_rate=Decimal("5"),
        )
        assert split.cess_amount == pytest.approx(5000, abs=1)

    def test_gst_engine_zero_rate(self):
        split = GSTEngine.calculate_tax(
            origin_state_code="27",
            place_of_supply_state_code="27",
            base_amount=Decimal("100000"),
            gst_rate=Decimal("0"),
        )
        assert split.total_tax == 0

    def test_gst_engine_negative_base_raises(self):
        with pytest.raises(ValueError):
            GSTEngine.calculate_tax(
                origin_state_code="27",
                place_of_supply_state_code="27",
                base_amount=Decimal("-100"),
                gst_rate=Decimal("18"),
            )

    def test_gst_non_gst_tenant_zero_tax(self, db_session, client):
        tenant = _seed_tenant(db_session, gstin=None, tax_mode="NON_GST")
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 201
        data = resp.json()
        assert Decimal(data["cgst_amount"]) == 0
        assert Decimal(data["sgst_amount"]) == 0
        assert Decimal(data["igst_amount"]) == 0

    def test_gst_gstr1_report_structure(self, db_session, client):
        tenant = _seed_tenant(db_session, gstin="27AAPFU0939F1ZV")
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        client.post("/api/v1/invoices", json=payload, headers=headers)

        resp = client.get(
            "/api/v1/gst/gstr1",
            params={"start_date": "2026-04-01", "end_date": "2027-03-31"},
            headers=headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "b2b" in data
        assert "b2cl" in data
        assert "b2cs" in data
        assert "cdnr" in data
        assert "cdnur" in data
        assert "hsn_summary" in data

    def test_gst_gstr2_report_structure(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.get(
            "/api/v1/gst/gstr2",
            params={"start_date": "2026-04-01", "end_date": "2027-03-31"},
            headers=headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "b2b_purchases" in data
        assert "b2bur_purchases" in data
        assert "hsn_summary" in data

    def test_gst_gstr3b_report(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.get(
            "/api/v1/reports/gst/gstr3b",
            params={"start_date": "2026-04-01", "end_date": "2026-04-30"},
            headers=headers,
        )
        assert resp.status_code == 200

    def test_gst_gstin_validation(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.get("/api/v1/gst/validate-gstin/27AAPFU0939F1ZV", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["valid"] is True

    def test_gst_invalid_gstin_rejected(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.get("/api/v1/gst/validate-gstin/INVALID", headers=headers)
        assert resp.status_code == 400

    def test_gst_round_off(self, db_session, client):
        tenant = _seed_tenant(db_session, gstin="27AAPFU0939F1ZV")
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant, gst_rate=Decimal("18.00"))
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, qty=3, rate="3333.33", pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 201
        data = resp.json()
        total = Decimal(data["total"])
        subtotal = Decimal(data["subtotal"])
        cgst = Decimal(data["cgst_amount"])
        sgst = Decimal(data["sgst_amount"])
        round_off = Decimal(data.get("round_off", "0"))
        assert total == subtotal + cgst + sgst + round_off


# ──────────────────────────────────────────────────────────────────────
# P5 — Offline Sync Validation (Idempotency & Conflict Prevention)
# ──────────────────────────────────────────────────────────────────────

class TestP5_OfflineSyncValidation:

    def test_duplicate_invoice_number_rejected(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant)
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id)
        payload["invoice_number"] = "DUP-001"
        resp1 = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp1.status_code == 201

        payload2 = _make_invoice_payload(contact.id, product.id)
        payload2["invoice_number"] = "DUP-001"
        resp2 = client.post("/api/v1/invoices", json=payload2, headers=headers)
        assert resp2.status_code == 400

    def test_idempotency_key_prevents_duplicate(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)
        idempotency_key = str(uuid.uuid4())
        headers["Idempotency-Key"] = idempotency_key

        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp1 = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp1.status_code == 201

        headers2 = _auth(user, tenant)
        headers2["Idempotency-Key"] = idempotency_key
        payload2 = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp2 = client.post("/api/v1/invoices", json=payload2, headers=headers2)
        assert resp2.status_code == 201
        assert resp2.headers.get("Idempotency-Replayed") == "true"
        assert resp2.json()["id"] == resp1.json()["id"]
        assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 1

    def test_idempotency_key_rejects_changed_retry_payload(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)
        headers["Idempotency-Key"] = str(uuid.uuid4())
        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        first = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert first.status_code == 201
        changed = dict(payload)
        changed["notes"] = "This is not the original operation"
        retry = client.post("/api/v1/invoices", json=changed, headers=headers)
        assert retry.status_code == 422
        assert retry.json()["code"] == "IDEMPOTENCY_PAYLOAD_MISMATCH"
        assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 1

    def test_cancelled_invoice_cannot_be_edited(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)

        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        inv_id = resp.json()["id"]

        client.post(f"/api/v1/invoices/{inv_id}/cancel", headers=headers)

        resp = client.delete(f"/api/v1/invoices/{inv_id}", headers=headers)
        assert resp.status_code in (400, 404, 422)


# ──────────────────────────────────────────────────────────────────────
# P6 — Performance Benchmarks
# ──────────────────────────────────────────────────────────────────────

class TestP6_Performance:

    def _time_request(self, client, method, url, **kwargs):
        start = time.monotonic()
        resp = getattr(client, method)(url, **kwargs)
        elapsed = time.monotonic() - start
        return resp, elapsed

    def test_login_performance(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        resp, elapsed = self._time_request(
            client, "post", "/api/v1/auth/login",
            json={"email": user.email, "password": "Test@1234"},
        )
        assert resp.status_code == 200
        assert elapsed < 5.0, f"Login took {elapsed:.2f}s"

    def test_dashboard_performance(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp, elapsed = self._time_request(
            client, "get", "/api/v1/dashboard/metrics", headers=headers,
        )
        assert resp.status_code == 200
        assert elapsed < 15.0, f"Dashboard took {elapsed:.2f}s"

    def test_invoice_creation_performance(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        contact = _seed_contact(db_session, tenant, gstin="27AAACB1234F1Z5", state_code="27")
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(user, tenant)
        payload = _make_invoice_payload(contact.id, product.id, pos_state="27")

        resp, elapsed = self._time_request(
            client, "post", "/api/v1/invoices", json=payload, headers=headers,
        )
        assert resp.status_code == 201
        assert elapsed < 5.0, f"Invoice creation took {elapsed:.2f}s"

    def test_trial_balance_performance(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp, elapsed = self._time_request(
            client, "get", "/api/v1/reports/trial-balance",
            params={"as_of_date": str(date.today())}, headers=headers,
        )
        assert resp.status_code == 200
        assert elapsed < 5.0, f"Trial balance took {elapsed:.2f}s"

    def test_invoice_list_pagination_performance(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp, elapsed = self._time_request(
            client, "get", "/api/v1/invoices",
            params={"page": 1, "limit": 50}, headers=headers,
        )
        assert resp.status_code == 200
        assert elapsed < 5.0

    def test_search_endpoint_not_registered(self, db_session, client):
        """Finding: /api/v1/search endpoint is documented but not registered."""
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)
        resp = client.get("/api/v1/search", params={"q": "test"}, headers=headers)
        assert resp.status_code == 404


# ──────────────────────────────────────────────────────────────────────
# P7 — Security Audit
# ──────────────────────────────────────────────────────────────────────

class TestP7_Security:

    def test_jwt_invalid_token_rejected(self, client):
        resp = client.get(
            "/api/v1/invoices",
            headers={"Authorization": "Bearer invalid.token.here", "X-Tenant-ID": str(uuid.uuid4())},
        )
        assert resp.status_code == 401

    def test_jwt_expired_token_rejected(self, db_session, client):
        from datetime import datetime, timedelta, timezone
        import jwt as pyjwt
        from src.core.config import settings

        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        payload = {
            "sub": str(user.id),
            "exp": datetime.now(timezone.utc) - timedelta(hours=1),
            "iat": datetime.now(timezone.utc) - timedelta(hours=2),
            "type": "access",
        }
        expired_token = pyjwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
        resp = client.get(
            "/api/v1/invoices",
            headers={"Authorization": f"Bearer {expired_token}", "X-Tenant-ID": str(tenant.id)},
        )
        assert resp.status_code == 401

    def test_refresh_token_rejected_as_access(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        from src.core.security import create_refresh_token
        refresh = create_refresh_token(user_id=str(user.id))
        resp = client.get(
            "/api/v1/invoices",
            headers={"Authorization": f"Bearer {refresh}", "X-Tenant-ID": str(tenant.id)},
        )
        assert resp.status_code == 401

    def test_tenant_isolation_enforced(self, db_session, client):
        t1 = _seed_tenant(db_session)
        t2 = _seed_tenant(db_session, gstin="29BBBCT5678R1Z6")
        u1 = _seed_user(db_session, t1)
        _seed_contact(db_session, t1, name="T1 Contact")
        _seed_contact(db_session, t2, name="T2 Contact")
        headers = _auth(u1, t1)

        resp = client.get("/api/v1/masters/contacts", headers=headers)
        assert resp.status_code == 200
        names = [c["name"] for c in resp.json()]
        assert "T1 Contact" in names
        assert "T2 Contact" not in names

    def test_auditor_cannot_create_invoice(self, db_session, client):
        tenant = _seed_tenant(db_session)
        auditor = _seed_user(db_session, tenant, email="auditor@test.com", role="auditor")
        contact = _seed_contact(db_session, tenant)
        product = _seed_product(db_session, tenant)
        _seed_numbering_series(db_session, tenant)
        headers = _auth(auditor, tenant)

        payload = _make_invoice_payload(contact.id, product.id)
        resp = client.post("/api/v1/invoices", json=payload, headers=headers)
        assert resp.status_code == 403

    def test_salesperson_cannot_access_ledger(self, db_session, client):
        tenant = _seed_tenant(db_session)
        sales = _seed_user(db_session, tenant, email="sales@test.com", role="salesperson")
        headers = _auth(sales, tenant)

        resp = client.get(
            "/api/v1/accounting/journals",
            headers=headers,
        )
        assert resp.status_code == 403

    def test_password_strength_enforced(self, db_session, client):
        resp = client.post("/api/v1/auth/register", json={
            "email": f"weak_{uuid.uuid4().hex[:6]}@test.com",
            "password": "weak",
            "full_name": "Weak User",
            "company_legal_name": "Weak Corp",
        })
        assert resp.status_code in (400, 422)

    def test_audit_log_model_works(self, db_session, client):
        """Verify audit log infrastructure is functional."""
        tenant = _seed_tenant(db_session)
        log = AuditLog(
            tenant_id=tenant.id,
            action="test.action",
            entity_type="test",
            entity_id=tenant.id,
        )
        db_session.add(log)
        db_session.commit()
        logs = db_session.query(AuditLog).filter(AuditLog.tenant_id == tenant.id).all()
        assert len(logs) >= 1

    def test_nonexistent_resource_returns_404(self, db_session, client):
        tenant = _seed_tenant(db_session)
        user = _seed_user(db_session, tenant)
        headers = _auth(user, tenant)

        resp = client.get(f"/api/v1/invoices/{uuid.uuid4()}", headers=headers)
        assert resp.status_code == 404

    def test_health_endpoint_exists(self, client):
        resp = client.get("/health")
        assert resp.status_code in (200, 503)
