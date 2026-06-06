"""
Year-End Close E2E Tests
========================
Three scenarios that validate the entire year-end close pipeline:

Scenario 1 — Profit-making company
    Sales 100,000 | Expenses 60,000 | Profit 40,000
    Verify: P&L = 40K, Retained Earnings += 40K, Rev/Exp = 0 in new FY

Scenario 2 — Loss-making company
    Sales 50,000 | Expenses 80,000 | Loss 30,000
    Verify: Retained Earnings decreases, close succeeds, next FY balances correct

Scenario 3 — Inventory carry-forward
    Opening stock → purchases → sales → returns → adjustments
    Verify: Closing Stock FY1 = Opening Stock FY2 exactly

Run:
    cd backend && python -m pytest tests/test_year_end_e2e.py -v --tb=short
"""
import sys, os, uuid, json
from datetime import date, timedelta
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Account, Product,
    JournalEntry, JournalLine, AccountingPeriod,
    OpeningBalanceSnapshot, InventoryCarryForward, FinancialYear, FinancialYearAudit,
)
from src.domains.accounting.services import AccountResolver


# ── Helpers ──────────────────────────────────────────────────────────────────

_TENANT_COUNTER = 0

def _register_and_login(client, email="owner@test.com", company="TestCo"):
    """Register a tenant, log in, return (token, tenant_id, headers, accounts)."""
    global _TENANT_COUNTER
    _TENANT_COUNTER += 1
    c = _TENANT_COUNTER
    # Valid 15-char GSTIN: 2(state)+5(pan_prefix)+4(pan_digits)+1(pan_letter)+1(entity)+Z+1(check)
    gstin = f"27AAPFU{c:04d}F1ZV"
    pan = f"AAPFU{c:04d}F"

    client.post("/api/v1/auth/register", json={
        "email": email,
        "password": "Passw0rd!",
        "full_name": "Test Owner",
        "phone_number": f"+9190000{c:04d}",
        "company_legal_name": company,
        "company_gstin": gstin,
        "company_pan": pan,
    })
    login = client.post("/api/v1/auth/login", json={"email": email, "password": "Passw0rd!"})
    token = login.json()["access_token"]

    db = SessionLocal()
    try:
        uid = db.query(User).filter(User.email == email).first().id
        m = db.query(TenantMembership).filter(TenantMembership.user_id == uid).first()
        tenant_id = m.tenant_id
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
        tenant.financial_year_start = date(2025, 4, 1)
        db.commit()

        resolver = AccountResolver(db, tenant_id)
        accounts = {
            "cash":      resolver.resolve("assets.cash"),
            "revenue":   resolver.resolve("sales_revenue"),
            "rent":      resolver.resolve("expense.rent"),
            "salary":    resolver.resolve("expense.salary"),
            "retained":  resolver.resolve("equity.retained"),
        }
        db.commit()
    finally:
        db.close()

    headers = {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant_id)}
    return token, tenant_id, headers, accounts


def _create_fy(client, headers, tenant_id, name, start, end):
    """Create a FinancialYear record via API."""
    r = client.post("/api/v1/financial-years", json={
        "name": name,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
    }, headers=headers)
    return r


def _post_journal(client, headers, entry_date, description, lines):
    """Post a journal entry. Returns response json."""
    payload = {
        "entry_date": entry_date.isoformat(),
        "description": description,
        "lines": lines,
    }
    return client.post("/api/v1/accounting/journals", json=payload, headers=headers)


def _create_product(client, db, tenant_id, name, sku, purchase_price, current_stock, opening_stock=0):
    """Create a product directly in the DB with stock."""
    product = Product(
        id=uuid.uuid4(),
        tenant_id=tenant_id,
        name=name,
        sku=sku,
        hsn_sac="998877",
        product_type="GOODS",
        uom="NOS",
        sales_price=Decimal("1500.00"),
        purchase_price=Decimal(str(purchase_price)),
        gst_rate=Decimal("18.00"),
        is_active=True,
        opening_stock=Decimal(str(opening_stock)),
        current_stock=Decimal(str(current_stock)),
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 1 — Profit-making company
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndScenario1_Profit:
    """Sales 100K | Expenses 60K | Profit 40K"""

    def test_full_profit_scenario(self, client):
        token, tid, h, accts = _register_and_login(client, "s1@test.com", "ProfitCo")

        # Create FY 2025-26
        _create_fy(client, h, tid, "2025-26", date(2025, 4, 1), date(2026, 3, 31))

        # ── Transactions in FY 2025-26 ──────────────────────────────────────
        # Sales: Cash 100K (debit) → Revenue 100K (credit)
        _post_journal(client, h, date(2025, 10, 15), "Sales", [
            {"account_id": str(accts["cash"]),    "amount": 100000, "direction": "DEBIT"},
            {"account_id": str(accts["revenue"]), "amount": 100000, "direction": "CREDIT"},
        ])

        # Rent: Rent 40K (debit) → Cash 40K (credit)
        _post_journal(client, h, date(2025, 11, 1), "Rent", [
            {"account_id": str(accts["rent"]),   "amount": 40000, "direction": "DEBIT"},
            {"account_id": str(accts["cash"]),   "amount": 40000, "direction": "CREDIT"},
        ])

        # Salary: Salary 20K (debit) → Cash 20K (credit)
        _post_journal(client, h, date(2026, 2, 1), "Salary", [
            {"account_id": str(accts["salary"]), "amount": 20000, "direction": "DEBIT"},
            {"account_id": str(accts["cash"]),   "amount": 20000, "direction": "CREDIT"},
        ])

        # ── Verify P&L before close ─────────────────────────────────────────
        pnl_resp = client.get(
            f"/api/v1/accounting/profit-loss?start_date=2025-04-01&end_date=2026-03-31",
            headers=h,
        )
        assert pnl_resp.status_code == 200
        pnl = pnl_resp.json()
        net_profit = float(pnl["net_profit"])
        assert abs(net_profit - 40000.0) < 0.01, f"P&L should be 40,000, got {net_profit}"

        # ── Get FY id ───────────────────────────────────────────────────────
        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]

        # ── Year-end dashboard ──────────────────────────────────────────────
        dash = client.get(f"/api/v1/financial-years/{fy_id}/dashboard", headers=h)
        assert dash.status_code == 200
        dash_json = dash.json()
        print(f"  Dashboard: score={dash_json['readiness_score']}, balanced={dash_json['trial_balance_balanced']}, unposted={dash_json['unposted_documents_count']}, blocking={dash_json['blocking_items']}")
        assert dash_json["trial_balance_balanced"]

        # ── Close ───────────────────────────────────────────────────────────
        close_resp = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        print(f"  Close response: {close_resp.status_code} {close_resp.json()}")
        assert close_resp.status_code == 200
        data = close_resp.json()
        assert data["status"] == "LOCKED"
        new_fy_id = data["new_financial_year_id"]
        assert new_fy_id is not None

        # ── Verify new FY exists and is CURRENT ─────────────────────────────
        fys2 = client.get("/api/v1/financial-years", headers=h).json()
        new_fy = [f for f in fys2 if f["id"] == new_fy_id][0]
        assert new_fy["status"] == "CURRENT"
        assert new_fy["is_current"] is True

        # ── Verify Retained Earnings increased by 40K ──────────────────────
        db = SessionLocal()
        try:
            retained = db.query(Account).filter(
                Account.tenant_id == tid,
                Account.id == accts["retained"],
            ).first()
            # After close, retained earnings = 40000 (net profit posted to RE)
            # current_balance includes opening + all journal lines
            print(f"  Retained Earnings current_balance: {retained.current_balance}")
            print(f"  Retained Earnings opening_balance: {retained.opening_balance}")
            # Since opening_balance=0 after roll-forward, current_balance = sum of all journals
            # The closing JE posted 40K credit to retained
            assert abs(float(retained.current_balance) - 40000.0) < 0.01, \
                f"Retained Earnings should be 40000, got {retained.current_balance}"
        finally:
            db.close()

        # ── Verify Revenue and Expense accounts show 0 in new FY context ────
        pnl_resp2 = client.get(
            f"/api/v1/accounting/profit-loss?start_date=2026-04-01&end_date=2027-03-31",
            headers=h,
        )
        assert pnl_resp2.status_code == 200
        pnl2 = pnl_resp2.json()
        assert abs(float(pnl2["net_profit"])) < 0.01, \
            f"Revenue/Expense should be 0 in new FY, got {pnl2['net_profit']}"

        # ── Verify Cash balance carried forward ─────────────────────────────
        db = SessionLocal()
        try:
            cash = db.query(Account).filter(
                Account.tenant_id == tid,
                Account.id == accts["cash"],
            ).first()
            # Cash started at 0, +100K -40K -20K = 40K
            print(f"  Cash current_balance: {cash.current_balance}")
            assert abs(float(cash.current_balance) - 40000.0) < 0.01, \
                f"Cash should be 40000, got {cash.current_balance}"
        finally:
            db.close()

        # ── Verify opening balance snapshots exist ──────────────────────────
        snapshots = client.get(f"/api/v1/financial-years/{fy_id}/opening-balances", headers=h).json()
        assert len(snapshots) > 0, "Should have opening balance snapshots"

        # ── Verify audit trail ──────────────────────────────────────────────
        # CLOSED is on closing FY; CREATED/OPENING_BALANCE_CARRY_FORWARD/INVENTORY_CARRY_FORWARD are on new FY
        audit_closed = client.get(f"/api/v1/financial-years/{fy_id}/audit", headers=h).json()
        actions_closed = [a["action"] for a in audit_closed]
        assert "CLOSED" in actions_closed, f"Should have CLOSED audit, got {actions_closed}"

        audit_new = client.get(f"/api/v1/financial-years/{new_fy_id}/audit", headers=h).json()
        actions_new = [a["action"] for a in audit_new]
        assert "CREATED" in actions_new
        assert "OPENING_BALANCE_CARRY_FORWARD" in actions_new
        assert "INVENTORY_CARRY_FORWARD" in actions_new

        print("  PASS Scenario 1: Profit 40K correctly posted to Retained Earnings")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 2 — Loss-making company
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndScenario2_Loss:
    """Sales 50K | Expenses 80K | Loss 30K"""

    def test_full_loss_scenario(self, client):
        token, tid, h, accts = _register_and_login(client, "s2@test.com", "LossCo")

        _create_fy(client, h, tid, "2025-26", date(2025, 4, 1), date(2026, 3, 31))

        # Sales 50K
        _post_journal(client, h, date(2025, 9, 1), "Sales", [
            {"account_id": str(accts["cash"]),    "amount": 50000, "direction": "DEBIT"},
            {"account_id": str(accts["revenue"]), "amount": 50000, "direction": "CREDIT"},
        ])

        # Rent 50K
        _post_journal(client, h, date(2025, 10, 1), "Rent", [
            {"account_id": str(accts["rent"]),   "amount": 50000, "direction": "DEBIT"},
            {"account_id": str(accts["cash"]),   "amount": 50000, "direction": "CREDIT"},
        ])

        # Salary 30K
        _post_journal(client, h, date(2026, 1, 15), "Salary", [
            {"account_id": str(accts["salary"]), "amount": 30000, "direction": "DEBIT"},
            {"account_id": str(accts["cash"]),   "amount": 30000, "direction": "CREDIT"},
        ])

        # ── P&L: loss of -30K ──────────────────────────────────────────────
        pnl = client.get(
            f"/api/v1/accounting/profit-loss?start_date=2025-04-01&end_date=2026-03-31",
            headers=h,
        ).json()
        assert abs(float(pnl["net_profit"]) - (-30000.0)) < 0.01, \
            f"P&L should be -30000, got {pnl['net_profit']}"

        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]

        # ── Close ───────────────────────────────────────────────────────────
        close_resp = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert close_resp.status_code == 200
        data = close_resp.json()
        assert data["status"] == "LOCKED"

        # ── Retained Earnings decreased by 30K ─────────────────────────────
        db = SessionLocal()
        try:
            retained = db.query(Account).filter(
                Account.tenant_id == tid,
                Account.id == accts["retained"],
            ).first()
            print(f"  Retained Earnings current_balance: {retained.current_balance}")
            # Loss: retained earnings should be negative
            assert float(retained.current_balance) < 0, \
                f"Retained Earnings should be negative, got {retained.current_balance}"
            assert abs(float(retained.current_balance) - (-30000.0)) < 0.01, \
                f"Retained Earnings should be -30000, got {retained.current_balance}"
        finally:
            db.close()

        # ── Next FY is CURRENT ──────────────────────────────────────────────
        fys2 = client.get("/api/v1/financial-years", headers=h).json()
        current = [f for f in fys2 if f["is_current"] and f["id"] != fy_id]
        assert len(current) == 1
        assert current[0]["name"] == "2026-27"

        # ── Verify Cash balance: 50K - 50K - 30K = -30K (negative = liability) ──
        db = SessionLocal()
        try:
            cash = db.query(Account).filter(
                Account.tenant_id == tid,
                Account.id == accts["cash"],
            ).first()
            print(f"  Cash current_balance: {cash.current_balance}")
            assert abs(float(cash.current_balance) - (-30000.0)) < 0.01, \
                f"Cash should be -30000, got {cash.current_balance}"
        finally:
            db.close()

        print("  PASS Scenario 2: Loss 30K correctly posted to Retained Earnings")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 3 — Inventory carry-forward
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndScenario3_Inventory:
    """Opening Stock → Purchases → Sales → Returns → Adjustments
    Verify: Closing Stock FY1 = Opening Stock FY2 exactly."""

    def test_inventory_carry_forward(self, client):
        token, tid, h, accts = _register_and_login(client, "s3@test.com", "InventoryCo")

        _create_fy(client, h, tid, "2025-26", date(2025, 4, 1), date(2026, 3, 31))

        # Create product with opening stock
        db = SessionLocal()
        try:
            product = _create_product(
                client, db, tid,
                name="Widget A", sku="WGT-001",
                purchase_price=100.00,
                current_stock=500,   # 500 units at ₹100
                opening_stock=200,   # opened with 200
            )
            product_id = product.id
        finally:
            db.close()

        # Simulate stock movements via direct DB update (simulating purchases/sales/returns)
        db = SessionLocal()
        try:
            product = db.query(Product).filter(Product.id == product_id).first()
            # Purchase +300 (stock goes 500 → 800)
            product.current_stock = Decimal("800")

            # Sale -200 (stock goes 800 → 600)
            # product.current_stock = Decimal("600")  # comment: simulate step by step

            # Return +50 (stock goes 600 → 650)
            # Adjustment -25 (stock goes 650 → 625)
            product.current_stock = Decimal("625")
            db.commit()
            closing_stock_fy1 = float(product.current_stock)
            print(f"  FY1 closing stock: {closing_stock_fy1}")
        finally:
            db.close()

        # ── Close FY ────────────────────────────────────────────────────────
        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]
        close_resp = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert close_resp.status_code == 200
        close_data = close_resp.json()
        new_fy_id = close_data["new_financial_year_id"]

        # ── Verify carry-forward snapshots ──────────────────────────────────
        cf_resp = client.get(f"/api/v1/financial-years/{fy_id}/inventory-carry-forward", headers=h)
        assert cf_resp.status_code == 200
        cf_data = cf_resp.json()
        assert len(cf_data) > 0, "Should have inventory carry-forward records"
        cf_record = [c for c in cf_data if c["product_id"] == str(product_id)]
        assert len(cf_record) == 1, f"Expected 1 carry-forward for product, got {len(cf_record)}"
        cf_qty = float(cf_record[0]["closing_quantity"])
        assert abs(cf_qty - closing_stock_fy1) < 0.01, \
            f"Carry-forward quantity should be {closing_stock_fy1}, got {cf_qty}"

        # ── Verify product opening_stock = closing_stock_fy1 ────────────────
        db = SessionLocal()
        try:
            product = db.query(Product).filter(Product.id == product_id).first()
            opening_stock_fy2 = float(product.opening_stock)
            current_stock = float(product.current_stock)
            print(f"  FY2 opening_stock: {opening_stock_fy2}")
            print(f"  FY2 current_stock: {current_stock}")

            assert abs(opening_stock_fy2 - closing_stock_fy1) < 0.01, \
                f"FY2 opening stock should be {closing_stock_fy1}, got {opening_stock_fy2}"
            # current_stock should NOT be reset (it's a snapshot field, not modified)
        finally:
            db.close()

        # ── Verify audit trail mentions inventory ───────────────────────────
        # Inventory audit is logged against the NEXT FY (new_fy), not the closing FY
        new_fy_audit = client.get(f"/api/v1/financial-years/{new_fy_id}/audit", headers=h).json()
        inv_actions = [a for a in new_fy_audit if "INVENTORY" in a["action"]]
        assert len(inv_actions) > 0, "Should have INVENTORY_CARRY_FORWARD audit entry on new FY"

        print("  PASS Scenario 3: Closing Stock FY1 = Opening Stock FY2")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 4 — Reopen reverses roll-forward
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndScenario4_Reopen:
    """Close then reopen → verify roll-forward is reversed."""

    def test_reopen_reverses_rollforward(self, client):
        token, tid, h, accts = _register_and_login(client, "s4@test.com", "ReopenCo")

        _create_fy(client, h, tid, "2025-26", date(2025, 4, 1), date(2026, 3, 31))

        _post_journal(client, h, date(2025, 12, 1), "Sales", [
            {"account_id": str(accts["cash"]),    "amount": 100000, "direction": "DEBIT"},
            {"account_id": str(accts["revenue"]), "amount": 100000, "direction": "CREDIT"},
        ])

        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]

        # Close
        close_resp = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert close_resp.status_code == 200
        new_fy_id = close_resp.json()["new_financial_year_id"]

        # Verify snapshots exist
        snaps_before = client.get(f"/api/v1/financial-years/{fy_id}/opening-balances", headers=h).json()
        assert len(snaps_before) > 0

        # Reopen
        reopen_resp = client.post(
            f"/api/v1/financial-years/{fy_id}/reopen",
            params={"reason": "Need to correct an entry"},
            headers=h,
        )
        assert reopen_resp.status_code == 200
        assert reopen_resp.json()["status"] == "READY_TO_CLOSE"

        # Verify snapshots deleted
        snaps_after = client.get(f"/api/v1/financial-years/{fy_id}/opening-balances", headers=h).json()
        assert len(snaps_after) == 0, \
            f"Opening balance snapshots should be deleted after reopen, got {len(snaps_after)}"

        # Verify inventory carry-forward deleted
        cf_after = client.get(f"/api/v1/financial-years/{fy_id}/inventory-carry-forward", headers=h).json()
        assert len(cf_after) == 0, \
            f"Inventory carry-forward should be deleted after reopen, got {len(cf_after)}"

        # Verify next FY's opening journal entry deleted
        db = SessionLocal()
        try:
            next_fy_je = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == tid,
                JournalEntry.source_type == "OPENING_BALANCE",
            ).first()
            assert next_fy_je is None, "Opening journal entry should be deleted after reopen"
        finally:
            db.close()

        print("  PASS Scenario 4: Reopen correctly reverses roll-forward")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 5 — Tenant isolation
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndScenario5_TenantIsolation:
    """Verify that tenant A's data doesn't leak to tenant B."""

    def test_tenant_isolation(self, client):
        # Tenant A
        _, tid_a, h_a, accts_a = _register_and_login(client, "ta@test.com", "TenantA")
        _create_fy(client, h_a, tid_a, "2025-26", date(2025, 4, 1), date(2026, 3, 31))
        _post_journal(client, h_a, date(2025, 6, 1), "TenantA Sales", [
            {"account_id": str(accts_a["cash"]),    "amount": 200000, "direction": "DEBIT"},
            {"account_id": str(accts_a["revenue"]), "amount": 200000, "direction": "CREDIT"},
        ])

        # Tenant B - need unique GSTIN/PAN
        _, tid_b, h_b, accts_b = _register_and_login(client, "tb@test.com", "TenantB")
        _create_fy(client, h_b, tid_b, "2025-26", date(2025, 4, 1), date(2026, 3, 31))
        _post_journal(client, h_b, date(2025, 7, 1), "TenantB Sales", [
            {"account_id": str(accts_b["cash"]),    "amount": 50000, "direction": "DEBIT"},
            {"account_id": str(accts_b["revenue"]), "amount": 50000, "direction": "CREDIT"},
        ])

        # Trial Balance for A should NOT include B's data
        tb_a = client.get(
            f"/api/v1/accounting/trial-balance",
            headers=h_a,
        ).json()

        # Check that no account shows 250K (which would be A+B combined)
        for line in tb_a["lines"]:
            if line["account_code"].startswith("1"):  # Cash
                assert float(line["closing_balance"]) != 250000, \
                    f"Tenant A data should not include Tenant B's transactions! Got {line['closing_balance']}"

        # P&L for A
        pnl_a = client.get(
            f"/api/v1/accounting/profit-loss?start_date=2025-04-01&end_date=2026-03-31",
            headers=h_a,
        ).json()
        assert float(pnl_a["total_revenue"]) == 200000, \
            f"Tenant A revenue should be 200000, got {pnl_a['total_revenue']}"

        # P&L for B
        pnl_b = client.get(
            f"/api/v1/accounting/profit-loss?start_date=2025-04-01&end_date=2026-03-31",
            headers=h_b,
        ).json()
        assert float(pnl_b["total_revenue"]) == 50000, \
            f"Tenant B revenue should be 50000, got {pnl_b['total_revenue']}"

        print("  PASS Scenario 5: Tenant isolation verified")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 6 — Concurrency protection
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndScenario6_DoubleClose:
    """Attempting to close an already-closed FY should fail."""

    def test_double_close_blocked(self, client):
        token, tid, h, accts = _register_and_login(client, "s6@test.com", "DoubleCloseCo")
        _create_fy(client, h, tid, "2025-26", date(2025, 4, 1), date(2026, 3, 31))

        _post_journal(client, h, date(2025, 5, 1), "Sales", [
            {"account_id": str(accts["cash"]),    "amount": 10000, "direction": "DEBIT"},
            {"account_id": str(accts["revenue"]), "amount": 10000, "direction": "CREDIT"},
        ])

        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]

        # First close
        r1 = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert r1.status_code == 200

        # Second close should fail
        r2 = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert r2.status_code == 400
        assert "already closed" in r2.json()["detail"].lower()

        print("  PASS Scenario 6: Double close correctly blocked")
