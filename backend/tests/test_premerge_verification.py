"""
Pre-Merge Verification Tests
============================
Comprehensive E2E tests to verify GST toggle doesn't break existing functionality.

Test 1 — GST_REGULAR: Intra-state invoice (CGST+SGST)
Test 2 — GST_REGULAR: Interstate invoice (IGST)
Test 3 — GST_REGULAR: GST reports (GSTR-1)
Test 4 — NON_GST: Invoice forces GST rate to zero
Test 5 — Year-end close: GST_REGULAR company
Test 6 — Year-end close: NON_GST company
Test 7 — GST toggle preserves company data
Test 8 — Bill creation under both modes

Run:
    cd backend && python -m pytest tests/test_premerge_verification.py -v --tb=short
"""
import sys, os, uuid
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import SessionLocal
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Account, Product,
    FinancialYear, FinancialYearAudit, TenantSetting,
)
from src.domains.accounting.services import AccountResolver


_TENANT_COUNTER = 9000


def _register_and_login(client, email="verify@test.com", company="VerifyCo", gstin=None, tax_mode="NON_GST"):
    """Register, login, set up FY, return (headers, tenant_id).

    If tax_mode is GST_REGULAR or GST_COMPOSITION, toggles after registration.
    """
    global _TENANT_COUNTER
    _TENANT_COUNTER += 1
    c = _TENANT_COUNTER

    if gstin is None and tax_mode in ("GST_REGULAR", "GST_COMPOSITION"):
        gstin = f"27AAPFU{c:04d}F1ZV"

    body = {
        "email": email,
        "password": "Passw0rd!",
        "full_name": "Verify Owner",
        "company_legal_name": company,
    }
    if gstin:
        body["company_gstin"] = gstin

    client.post("/api/v1/auth/register", json=body)
    login = client.post("/api/v1/auth/login", json={"email": email, "password": "Passw0rd!"})
    assert login.status_code == 200, f"Login failed: {login.json()}"
    token = login.json()["access_token"]

    db = SessionLocal()
    try:
        uid = db.query(User).filter(User.email == email).first().id
        m = db.query(TenantMembership).filter(TenantMembership.user_id == uid).first()
        tenant_id = m.tenant_id

        tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
        tenant.financial_year_start = date(2025, 4, 1)

        if tax_mode in ("GST_REGULAR", "GST_COMPOSITION"):
            tenant.tax_mode = tax_mode

        setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
        if not setting:
            setting = TenantSetting(tenant_id=tenant_id)
            db.add(setting)
        if gstin:
            setting.origin_state_code = gstin[:2]

        db.commit()
    finally:
        db.close()

    headers = {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant_id)}

    # Create FY 2025-26
    client.post("/api/v1/financial-years", json={
        "name": "2025-26",
        "start_date": "2025-04-01",
        "end_date": "2026-03-31",
    }, headers=headers)

    return headers, str(tenant_id)


def _create_product_via_api(client, headers, name="TestProduct", hsn_sac="998311", gst_rate=18):
    res = client.post("/api/v1/masters/products", json={
        "name": name,
        "product_type": "SERVICE",
        "uom": "NOS",
        "hsn_sac": hsn_sac,
        "gst_rate": gst_rate,
        "sales_price": 1000,
        "purchase_price": 800,
    }, headers=headers)
    assert res.status_code == 201, f"Product creation failed: {res.status_code} {res.json()}"
    return res.json()["id"]


def _create_contact_via_api(client, headers, name="TestContact", state_code="27", gstin=None, registration_type="REGULAR"):
    body = {
        "name": name,
        "contact_type": "CUSTOMER",
        "state_code": state_code,
        "registration_type": registration_type,
        "billing_address": {
            "street": "123 Test St",
            "city": "Mumbai",
            "state": "Maharashtra",
            "state_code": state_code,
            "pincode": "400001",
        },
    }
    if gstin:
        body["gstin"] = gstin
    res = client.post("/api/v1/masters/contacts", json=body, headers=headers)
    assert res.status_code == 201, f"Contact creation failed: {res.status_code} {res.json()}"
    return res.json()["id"]


def _create_bill_via_api(client, headers, contact_id, product_id, rate=1000, pos_state_code="27"):
    res = client.post("/api/v1/bills", json={
        "bill_number": f"BILL-{uuid.uuid4().hex[:8].upper()}",
        "contact_id": contact_id,
        "issue_date": "2025-10-01",
        "due_date": "2025-11-01",
        "pos_state_code": pos_state_code,
        "line_items": [{
            "product_id": product_id,
            "description": "Test Bill Item",
            "quantity": 1,
            "rate": rate,
            "discount": 0,
            "hsn_sac": "998311",
            "gst_rate": 18,
        }],
    }, headers=headers)
    return res


# ══════════════════════════════════════════════════════════════════════════════
# TEST 1 — GST_REGULAR: Intra-state invoice (CGST + SGST split)
# ══════════════════════════════════════════════════════════════════════════════

class TestGstRegularIntraState:
    """Intra-state: origin=27 (MH), POS=27 (MH) → CGST + SGST each = rate/2."""

    def test_intra_state_cgst_sgst(self, client: TestClient):
        h, tid = _register_and_login(client, "intra@test.com", "IntraCo", tax_mode="GST_REGULAR")
        pid = _create_product_via_api(client, h, "Consulting", "998311", 18)
        cid = _create_contact_via_api(client, h, "Mumbai Customer", state_code="27")

        inv_res = client.post("/api/v1/invoices", json={
            "contact_id": cid,
            "issue_date": "2025-10-15",
            "due_date": "2025-11-15",
            "pos_state_code": "27",
            "line_items": [{
                "product_id": pid,
                "description": "Consulting Service",
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,
            }],
        }, headers=h)
        assert inv_res.status_code == 201, f"Invoice creation failed: {inv_res.status_code} {inv_res.json()}"
        inv = inv_res.json()

        line = inv["lines"][0]
        # Base: 10000, CGST 9% = 900, SGST 9% = 900, IGST = 0
        assert float(line["cgst_rate"]) == 9.0, f"CGST rate should be 9%, got {line['cgst_rate']}"
        assert float(line["sgst_rate"]) == 9.0, f"SGST rate should be 9%, got {line['sgst_rate']}"
        assert float(line["igst_rate"]) == 0.0, f"IGST rate should be 0%, got {line['igst_rate']}"
        assert abs(float(line["cgst_amount"]) - 900.0) < 0.01, f"CGST amount should be 900, got {line['cgst_amount']}"
        assert abs(float(line["sgst_amount"]) - 900.0) < 0.01, f"SGST amount should be 900, got {line['sgst_amount']}"
        assert abs(float(line["igst_amount"])) < 0.01, f"IGST amount should be 0, got {line['igst_amount']}"
        assert abs(float(inv["cgst_amount"]) - 900.0) < 0.01
        assert abs(float(inv["sgst_amount"]) - 900.0) < 0.01

        # Invoice should be POSTED (auto_post ran)
        assert inv["status"] == "POSTED", f"Invoice status should be POSTED, got {inv['status']}"


# ══════════════════════════════════════════════════════════════════════════════
# TEST 2 — GST_REGULAR: Interstate invoice (IGST)
# ══════════════════════════════════════════════════════════════════════════════

class TestGstRegularInterState:
    """Inter-state: origin=27 (MH), POS=06 (GJ) → IGST = full rate."""

    def test_inter_state_igst(self, client: TestClient):
        h, tid = _register_and_login(client, "inter@test.com", "InterCo", tax_mode="GST_REGULAR")
        pid = _create_product_via_api(client, h, "Software", "998311", 18)
        # Contact from Gujarat (state_code=06)
        cid = _create_contact_via_api(client, h, "Gujarat Customer", state_code="06")

        inv_res = client.post("/api/v1/invoices", json={
            "contact_id": cid,
            "issue_date": "2025-10-15",
            "due_date": "2025-11-15",
            "pos_state_code": "06",
            "line_items": [{
                "product_id": pid,
                "description": "Software License",
                "quantity": 1,
                "rate": 50000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,
            }],
        }, headers=h)
        assert inv_res.status_code == 201, f"Invoice failed: {inv_res.status_code} {inv_res.json()}"
        inv = inv_res.json()
        line = inv["lines"][0]

        # IGST should be 18% of 50000 = 9000
        assert float(line["cgst_rate"]) == 0.0, f"CGST should be 0 for interstate, got {line['cgst_rate']}"
        assert float(line["sgst_rate"]) == 0.0, f"SGST should be 0 for interstate, got {line['sgst_rate']}"
        assert float(line["igst_rate"]) == 18.0, f"IGST rate should be 18%, got {line['igst_rate']}"
        assert abs(float(line["igst_amount"]) - 9000.0) < 0.01, f"IGST should be 9000, got {line['igst_amount']}"
        assert abs(float(line["cgst_amount"])) < 0.01, f"CGST should be 0, got {line['cgst_amount']}"
        assert abs(float(line["sgst_amount"])) < 0.01, f"SGST should be 0, got {line['sgst_amount']}"
        assert inv["status"] == "POSTED"


# ══════════════════════════════════════════════════════════════════════════════
# TEST 3 — GST_REGULAR: GSTR-1 report returns valid data
# ══════════════════════════════════════════════════════════════════════════════

class TestGstRegularReports:
    """Verify GSTR-1 returns data for a GST_REGULAR company with posted invoices."""

    def test_gstr1_with_invoices(self, client: TestClient):
        h, tid = _register_and_login(client, "reports@test.com", "ReportCo", tax_mode="GST_REGULAR")
        pid = _create_product_via_api(client, h, "Service", "998311", 18)
        cid = _create_contact_via_api(client, h, "Report Customer", state_code="27")

        # Create an invoice (auto_posted to POSTED)
        inv_res = client.post("/api/v1/invoices", json={
            "contact_id": cid,
            "issue_date": "2025-10-15",
            "due_date": "2025-11-15",
            "pos_state_code": "27",
            "line_items": [{
                "product_id": pid,
                "description": "Professional Service",
                "quantity": 1,
                "rate": 25000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,
            }],
        }, headers=h)
        assert inv_res.status_code == 201

        # Fetch GSTR-1 for Oct 2025 — check both b2b and b2cs
        gstr1 = client.get("/api/v1/gst/gstr1?start_date=2025-10-01&end_date=2025-10-31", headers=h)
        assert gstr1.status_code == 200, f"GSTR-1 failed: {gstr1.status_code}"
        data = gstr1.json()

        # Invoice is posted → should appear in either b2b (if contact has GSTIN) or b2cs
        total_entries = len(data.get("b2b", [])) + len(data.get("b2cs", []))
        assert total_entries > 0, f"GSTR-1 should have entries in b2b or b2cs, got b2b={data.get('b2b')}, b2cs={data.get('b2cs')}"

        # Verify HSN summary exists
        assert "hsn_summary" in data, "GSTR-1 should contain hsn_summary"


# ══════════════════════════════════════════════════════════════════════════════
# TEST 4 — NON_GST: Invoice forces GST rate to zero
# ══════════════════════════════════════════════════════════════════════════════

class TestNonGstInvoice:
    """NON_GST mode: all GST amounts must be forced to zero regardless of input rate."""

    def test_non_gst_zero_tax(self, client: TestClient):
        h, tid = _register_and_login(client, "nongst@test.com", "NonGstCo", tax_mode="NON_GST")

        # Verify company state
        comp = client.get(f"/api/v1/companies/{tid}", headers=h).json()
        assert comp["tax_mode"] == "NON_GST"
        assert comp["gst_enabled"] is False

        pid = _create_product_via_api(client, h, "ServiceNoGst", "998311", 18)
        cid = _create_contact_via_api(client, h, "NoGst Customer", state_code="27")

        inv_res = client.post("/api/v1/invoices", json={
            "contact_id": cid,
            "issue_date": "2025-10-15",
            "due_date": "2025-11-15",
            "pos_state_code": "27",
            "line_items": [{
                "product_id": pid,
                "description": "Non-GST Service",
                "quantity": 2,
                "rate": 5000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,  # Should be forced to 0
            }],
        }, headers=h)
        assert inv_res.status_code == 201, f"Invoice failed: {inv_res.status_code} {inv_res.json()}"
        inv = inv_res.json()
        line = inv["lines"][0]

        # All tax must be zero
        assert float(line["gst_rate"]) == 0.0, f"GST rate forced to 0, got {line['gst_rate']}"
        assert float(line["cgst_rate"]) == 0.0
        assert float(line["sgst_rate"]) == 0.0
        assert float(line["igst_rate"]) == 0.0
        assert abs(float(line["cgst_amount"])) < 0.01
        assert abs(float(line["sgst_amount"])) < 0.01
        assert abs(float(line["igst_amount"])) < 0.01
        assert abs(float(inv["cgst_amount"])) < 0.01
        assert abs(float(inv["sgst_amount"])) < 0.01
        assert abs(float(inv["igst_amount"])) < 0.01

        # Subtotal: 2 * 5000 = 10000, total should equal subtotal (no tax)
        assert abs(float(inv["subtotal"]) - 10000.0) < 0.01
        assert inv["status"] == "POSTED"


# ══════════════════════════════════════════════════════════════════════════════
# TEST 5 — Year-end close: GST_REGULAR company
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndGstRegular:
    """Close a GST_REGULAR company with invoice revenue."""

    def test_close_gst_company(self, client: TestClient):
        h, tid = _register_and_login(client, "yegst@test.com", "YeGstCo", tax_mode="GST_REGULAR")
        pid = _create_product_via_api(client, h, "GSTService", "998311", 18)
        cid = _create_contact_via_api(client, h, "GST Customer", state_code="27")

        # Create an invoice in FY 2025-26
        inv_res = client.post("/api/v1/invoices", json={
            "contact_id": cid,
            "issue_date": "2025-10-15",
            "due_date": "2025-11-15",
            "pos_state_code": "27",
            "line_items": [{
                "product_id": pid,
                "description": "GST Revenue",
                "quantity": 1,
                "rate": 100000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,
            }],
        }, headers=h)
        assert inv_res.status_code == 201
        inv = inv_res.json()

        # Verify invoice has GST before close
        assert float(inv["cgst_amount"]) > 0, "CGST should be non-zero for GST invoice"
        assert float(inv["sgst_amount"]) > 0, "SGST should be non-zero for GST invoice"
        assert abs(float(inv["cgst_amount"]) - 9000.0) < 0.01

        # Get FY id
        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]

        # Dashboard check
        dash = client.get(f"/api/v1/financial-years/{fy_id}/dashboard", headers=h)
        assert dash.status_code == 200
        assert dash.json()["trial_balance_balanced"]

        # Verify P&L BEFORE close (closing JE zeroes revenue/expense)
        pnl_before = client.get(
            "/api/v1/accounting/profit-loss?start_date=2025-04-01&end_date=2026-03-31",
            headers=h,
        )
        assert pnl_before.status_code == 200
        net_before = float(pnl_before.json()["net_profit"])
        # Revenue = 100000, so profit should be 100000
        assert abs(net_before - 100000.0) < 0.01, f"P&L before close should be 100000, got {net_before}"

        # Close
        close = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert close.status_code == 200, f"Close failed: {close.status_code} {close.json()}"
        data = close.json()
        assert data["status"] == "LOCKED"
        assert data["new_financial_year_id"] is not None

        # Verify new FY is CURRENT
        fys2 = client.get("/api/v1/financial-years", headers=h).json()
        new_fy = [f for f in fys2 if f["id"] == data["new_financial_year_id"]][0]
        assert new_fy["status"] == "CURRENT"
        assert new_fy["is_current"] is True


# ══════════════════════════════════════════════════════════════════════════════
# TEST 6 — Year-end close: NON_GST company
# ══════════════════════════════════════════════════════════════════════════════

class TestYearEndNonGst:
    """Close a NON_GST company — revenue should still reconcile."""

    def test_close_nongst_company(self, client: TestClient):
        h, tid = _register_and_login(client, "yenongst@test.com", "YeNonGstCo", tax_mode="NON_GST")

        pid = _create_product_via_api(client, h, "NoGSTService", "998311", 18)
        cid = _create_contact_via_api(client, h, "Non-GST Customer", state_code="27")

        # Create invoice — GST forced to 0
        inv_res = client.post("/api/v1/invoices", json={
            "contact_id": cid,
            "issue_date": "2025-10-15",
            "due_date": "2025-11-15",
            "pos_state_code": "27",
            "line_items": [{
                "product_id": pid,
                "description": "Non-GST Revenue",
                "quantity": 1,
                "rate": 75000,
                "discount": 0,
                "hsn_sac": "998311",
                "gst_rate": 18,
            }],
        }, headers=h)
        assert inv_res.status_code == 201
        inv = inv_res.json()
        # Verify no tax
        assert abs(float(inv["cgst_amount"])) < 0.01
        assert abs(float(inv["sgst_amount"])) < 0.01
        assert abs(float(inv["igst_amount"])) < 0.01

        # Verify P&L BEFORE close
        pnl_before = client.get(
            "/api/v1/accounting/profit-loss?start_date=2025-04-01&end_date=2026-03-31",
            headers=h,
        )
        assert pnl_before.status_code == 200
        net_before = float(pnl_before.json()["net_profit"])
        assert abs(net_before - 75000.0) < 0.01, f"P&L before close should be 75000, got {net_before}"

        # Close FY
        fys = client.get("/api/v1/financial-years", headers=h).json()
        fy_id = [f["id"] for f in fys if f["name"] == "2025-26"][0]

        dash = client.get(f"/api/v1/financial-years/{fy_id}/dashboard", headers=h)
        assert dash.json()["trial_balance_balanced"]

        close = client.post(f"/api/v1/financial-years/{fy_id}/close", headers=h)
        assert close.status_code == 200
        assert close.json()["status"] == "LOCKED"


# ══════════════════════════════════════════════════════════════════════════════
# TEST 7 — GST toggle round-trip preserves data
# ══════════════════════════════════════════════════════════════════════════════

class TestGstToggleRoundTrip:
    """Toggle ON→OFF→ON preserves company data."""

    def test_toggle_round_trip(self, client: TestClient):
        h, tid = _register_and_login(client, "toggle@test.com", "ToggleCo", tax_mode="NON_GST")

        # Verify starts as NON_GST
        comp = client.get(f"/api/v1/companies/{tid}", headers=h).json()
        assert comp["tax_mode"] == "NON_GST"
        assert comp["gst_enabled"] is False

        # Toggle to GST_REGULAR
        r1 = client.post(f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "GST_REGULAR"}, headers=h)
        assert r1.status_code == 200
        assert r1.json()["tax_mode"] == "GST_REGULAR"
        assert r1.json()["gst_enabled"] is True

        # Verify via GET
        comp2 = client.get(f"/api/v1/companies/{tid}", headers=h).json()
        assert comp2["tax_mode"] == "GST_REGULAR"
        assert comp2["gst_enabled"] is True
        assert comp2["legal_name"] == "ToggleCo"  # Data preserved

        # Toggle back to NON_GST
        r2 = client.post(f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "NON_GST"}, headers=h)
        assert r2.status_code == 200
        assert r2.json()["tax_mode"] == "NON_GST"
        assert r2.json()["gst_enabled"] is False

        # Company data still intact
        comp3 = client.get(f"/api/v1/companies/{tid}", headers=h).json()
        assert comp3["legal_name"] == "ToggleCo"
        assert comp3["tax_mode"] == "NON_GST"

        # Toggle back to GST_COMPOSITION
        r3 = client.post(f"/api/v1/companies/{tid}/gst-toggle",
            json={"tax_mode": "GST_COMPOSITION"}, headers=h)
        assert r3.status_code == 200
        assert r3.json()["tax_mode"] == "GST_COMPOSITION"
        assert r3.json()["gst_enabled"] is True


# ══════════════════════════════════════════════════════════════════════════════
# TEST 8 — Bill creation under both modes
# ══════════════════════════════════════════════════════════════════════════════

class TestBillCreationBothModes:
    """Bills should work correctly under both GST and NON_GST modes."""

    def test_bill_with_gst(self, client: TestClient):
        h, tid = _register_and_login(client, "billgst@test.com", "BillGstCo", tax_mode="GST_REGULAR")
        pid = _create_product_via_api(client, h, "GSTProduct", "998311", 18)

        # Bills require VENDOR contact
        body = {
            "name": "Vendor GST",
            "contact_type": "VENDOR",
            "state_code": "27",
            "registration_type": "REGULAR",
            "gstin": "27AABCT1234F1Z5",
            "billing_address": {
                "street": "456 Vendor St",
                "city": "Mumbai",
                "state": "Maharashtra",
                "state_code": "27",
                "pincode": "400001",
            },
        }
        cid_res = client.post("/api/v1/masters/contacts", json=body, headers=h)
        assert cid_res.status_code == 201, f"Vendor contact failed: {cid_res.status_code} {cid_res.json()}"
        cid = cid_res.json()["id"]

        bill = _create_bill_via_api(client, h, cid, pid, rate=20000)
        assert bill.status_code == 201, f"Bill creation failed: {bill.status_code} {bill.json()}"
        data = bill.json()
        line = data["lines"][0]
        # Intra-state CGST+SGST
        assert float(line["cgst_rate"]) == 9.0
        assert float(line["sgst_rate"]) == 9.0
        assert float(line["igst_rate"]) == 0.0
        assert abs(float(line["cgst_amount"]) - 1800.0) < 0.01
        assert abs(float(line["sgst_amount"]) - 1800.0) < 0.01

    def test_bill_non_gst(self, client: TestClient):
        h, tid = _register_and_login(client, "billnongst@test.com", "BillNonGstCo", tax_mode="NON_GST")

        pid = _create_product_via_api(client, h, "NonGSTProduct", "998311", 18)

        # Bills require VENDOR contact
        body = {
            "name": "Vendor Non-GST",
            "contact_type": "VENDOR",
            "state_code": "27",
            "registration_type": "CONSUMER",
            "billing_address": {
                "street": "789 Vendor St",
                "city": "Mumbai",
                "state": "Maharashtra",
                "state_code": "27",
                "pincode": "400001",
            },
        }
        cid_res = client.post("/api/v1/masters/contacts", json=body, headers=h)
        assert cid_res.status_code == 201, f"Vendor contact failed: {cid_res.status_code} {cid_res.json()}"
        cid = cid_res.json()["id"]

        bill = _create_bill_via_api(client, h, cid, pid, rate=20000)
        assert bill.status_code == 201, f"Bill failed: {bill.status_code} {bill.json()}"
        data = bill.json()
        line = data["lines"][0]
        # All GST forced to 0
        assert float(line["gst_rate"]) == 0.0, f"GST rate should be 0, got {line['gst_rate']}"
        assert float(line["cgst_rate"]) == 0.0
        assert float(line["sgst_rate"]) == 0.0
        assert float(line["igst_rate"]) == 0.0
        assert abs(float(line["cgst_amount"])) < 0.01
        assert abs(float(line["sgst_amount"])) < 0.01
        assert abs(float(line["igst_amount"])) < 0.01
