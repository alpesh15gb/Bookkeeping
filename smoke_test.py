#!/usr/bin/env python3
"""
POST-DEPLOYMENT PRODUCTION SMOKE TEST
Target: https://api.apexbooks.in
Commit: c658ae9

Run from any machine with network access:
  python3 smoke_test.py
"""
import requests
import sys
import json
from datetime import date, timedelta

BASE = "https://api.apexbooks.in/api/v1"
PASS_COUNT = 0
FAIL_COUNT = 0
RESULTS = []

def report(name, passed, detail=""):
    global PASS_COUNT, FAIL_COUNT
    status = "PASS" if passed else "FAIL"
    if passed:
        PASS_COUNT += 1
    else:
        FAIL_COUNT += 1
    RESULTS.append((name, status, detail))
    print(f"  [{status}] {name}")
    if detail and not passed:
        print(f"         {detail}")

def api(method, path, token=None, tenant_id=None, json_body=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if tenant_id:
        headers["X-Tenant-ID"] = tenant_id
    url = f"{BASE}{path}"
    if method == "GET":
        return requests.get(url, headers=headers, timeout=30)
    elif method == "POST":
        return requests.post(url, headers=headers, json=json_body, timeout=30)

# Use UUID to make emails unique per run
import uuid as _uuid
_run_id = _uuid.uuid4().hex[:8]

def get_tenant_id(token):
    r = api("GET", "/auth/memberships", token=token)
    if r.status_code == 200:
        members = r.json()
        if isinstance(members, list) and len(members) > 0:
            return members[0].get("tenant_id")
    return None

# ============================================================
# SMOKE TEST 1: Register WITHOUT GSTIN
# ============================================================
print("\n" + "=" * 70)
print("SMOKE TEST 1: Register WITHOUT GSTIN")
print("=" * 70)

r = api("POST", "/auth/register", json_body={
    "email": f"smoke_nongst_{_run_id}@test.com",
    "password": "SmokeT3st!@#",
    "full_name": "Smoke NonGST",
    "company_legal_name": "Smoke NonGST Corp",
})
report("Register without GSTIN", r.status_code == 201, f"status={r.status_code}")

if r.status_code == 201:
    r2 = api("POST", "/auth/login", json_body={
        "email": f"smoke_nongst_{_run_id}@test.com",
        "password": "SmokeT3st!@#"
    })
    token_nongst = r2.json().get("access_token")
    tid_nongst = get_tenant_id(token_nongst)

    # Check tenant config via company endpoint
    r3 = api("GET", f"/companies/{tid_nongst}", token=token_nongst)
    if r3.status_code == 200:
        data = r3.json()
        report("tax_mode = NON_GST", data.get("tax_mode") == "NON_GST",
               f"got {data.get('tax_mode')}")
        report("gstin = None", data.get("gstin") is None,
               f"got {data.get('gstin')}")
    else:
        report("Company retrieval", False, f"status={r3.status_code}")

# ============================================================
# SMOKE TEST 2: Register WITH GSTIN
# ============================================================
print("\n" + "=" * 70)
print("SMOKE TEST 2: Register WITH GSTIN (27 = Maharashtra)")
print("=" * 70)

# GSTIN must match: ^\d{2}[A-Z]{5}\d{4}[A-Z]\d[Z][A-Z\d]$
# Format: XX(2) + ALPHA(5) + DIGITS(4) + ALPHA(1) + DIGIT1-9(1) + Z(1) + ALNUM(1) = 15
gstin_digits = ''.join(c for c in _run_id if c.isdigit())[:4].zfill(4)
gstin_val = f"27AAAAA{gstin_digits}A1Z1"
pan_val = f"AAAAA{gstin_digits}A"
r = api("POST", "/auth/register", json_body={
    "email": f"smoke_gst_{_run_id}@test.com",
    "password": "SmokeT3st!@#",
    "full_name": "Smoke GST User",
    "company_legal_name": "Smoke GST Corp",
    "company_gstin": gstin_val,
    "company_pan": pan_val,
})
if r.status_code != 201:
    print(f"         Response: {r.text[:200]}")
report("Register with GSTIN", r.status_code == 201, f"status={r.status_code} gstin={gstin_val}")

token_gst = None
tid_gst = None
if r.status_code == 201:
    r2 = api("POST", "/auth/login", json_body={
        "email": f"smoke_gst_{_run_id}@test.com",
        "password": "SmokeT3st!@#"
    })
    token_gst = r2.json().get("access_token")
    tid_gst = get_tenant_id(token_gst)

    r3 = api("GET", f"/companies/{tid_gst}", token=token_gst)
    if r3.status_code == 200:
        data = r3.json()
        tax_mode = data.get("tax_mode")
        gstin = data.get("gstin")
        report("tax_mode = GST_REGULAR", tax_mode == "GST_REGULAR",
               f"got {tax_mode}")
        report("gstin = registered GSTIN", gstin == gstin_val,
               f"expected {gstin_val}, got {gstin}")

if token_gst and tid_gst:
    # ============================================================
    # SMOKE TEST 3: Create Product
    # ============================================================
    print("\n" + "=" * 70)
    print("SMOKE TEST 3: Create Product")
    print("=" * 70)

    r_prod = api("POST", "/masters/products", token=token_gst, tenant_id=tid_gst, json_body={
        "name": "Smoke Service",
        "product_type": "SERVICE",
        "uom": "HRS",
        "sales_price": 10000,
        "purchase_price": 0,
        "hsn_sac": "998314",
        "gst_rate": 18,
    })
    report("Create product", r_prod.status_code == 201, f"status={r_prod.status_code}")
    product_id = r_prod.json().get("id") if r_prod.status_code == 201 else None

    # ============================================================
    # SMOKE TEST 4: Create Contact
    # ============================================================
    print("\n" + "=" * 70)
    print("SMOKE TEST 4: Create Contact")
    print("=" * 70)

    # Intrastate contact (Maharashtra)
    r_contact_intra = api("POST", "/masters/contacts", token=token_gst, tenant_id=tid_gst, json_body={
        "name": "Smoke MH Customer",
        "contact_type": "CUSTOMER",
        "gstin": "27BBBBC5678D1Z2",
        "registration_type": "REGULAR",
        "state_code": "27",
        "billing_address": {
            "street": "1 St", "city": "Mumbai",
            "state": "Maharashtra", "state_code": "27",
            "pincode": "400001", "country": "India"
        }
    })
    report("Create intrastate contact", r_contact_intra.status_code == 201,
           f"status={r_contact_intra.status_code}")
    contact_intra_id = r_contact_intra.json().get("id") if r_contact_intra.status_code == 201 else None

    # Interstate contact (Karnataka)
    r_contact_inter = api("POST", "/masters/contacts", token=token_gst, tenant_id=tid_gst, json_body={
        "name": "Smoke KA Customer",
        "contact_type": "CUSTOMER",
        "gstin": "29AAACI5678B2Z2",
        "registration_type": "REGULAR",
        "state_code": "29",
        "billing_address": {
            "street": "1 St", "city": "Bangalore",
            "state": "Karnataka", "state_code": "29",
            "pincode": "560001", "country": "India"
        }
    })
    report("Create interstate contact", r_contact_inter.status_code == 201,
           f"status={r_contact_inter.status_code}")
    contact_inter_id = r_contact_inter.json().get("id") if r_contact_inter.status_code == 201 else None

    if product_id and contact_intra_id:
        # ============================================================
        # SMOKE TEST 5: Intrastate Invoice (CGST + SGST)
        # ============================================================
        print("\n" + "=" * 70)
        print("SMOKE TEST 5: Intrastate Invoice (POS=27, origin=27)")
        print("=" * 70)

        r_inv_intra = api("POST", "/invoices", token=token_gst, tenant_id=tid_gst, json_body={
            "contact_id": contact_intra_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today() + timedelta(days=30)),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": product_id,
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        })
        report("Create intrastate invoice", r_inv_intra.status_code == 201,
               f"status={r_inv_intra.status_code}")

        if r_inv_intra.status_code == 201:
            inv = r_inv_intra.json()
            line = inv.get("lines", [{}])[0]
            report("CGST rate = 9%", float(line.get("cgst_rate", 0)) == 9.0,
                   f"got {line.get('cgst_rate')}")
            report("CGST amount = 900", float(line.get("cgst_amount", 0)) == 900.0,
                   f"got {line.get('cgst_amount')}")
            report("SGST rate = 9%", float(line.get("sgst_rate", 0)) == 9.0,
                   f"got {line.get('sgst_rate')}")
            report("SGST amount = 900", float(line.get("sgst_amount", 0)) == 900.0,
                   f"got {line.get('sgst_amount')}")
            report("IGST = 0", float(line.get("igst_amount", 0)) == 0.0,
                   f"got {line.get('igst_amount')}")
            report("Total = 11800", float(inv.get("total", 0)) == 11800.0,
                   f"got {inv.get('total')}")

    if product_id and contact_inter_id:
        # ============================================================
        # SMOKE TEST 6: Interstate Invoice (IGST)
        # ============================================================
        print("\n" + "=" * 70)
        print("SMOKE TEST 6: Interstate Invoice (POS=29, origin=27)")
        print("=" * 70)

        r_inv_inter = api("POST", "/invoices", token=token_gst, tenant_id=tid_gst, json_body={
            "contact_id": contact_inter_id,
            "issue_date": str(date.today()),
            "due_date": str(date.today() + timedelta(days=30)),
            "pos_state_code": "29",
            "line_items": [{
                "product_id": product_id,
                "quantity": 1,
                "rate": 10000,
                "discount": 0,
                "hsn_sac": "998314",
                "gst_rate": 18,
            }]
        })
        report("Create interstate invoice", r_inv_inter.status_code == 201,
               f"status={r_inv_inter.status_code}")

        if r_inv_inter.status_code == 201:
            inv = r_inv_inter.json()
            line = inv.get("lines", [{}])[0]
            report("CGST = 0", float(line.get("cgst_amount", 0)) == 0.0,
                   f"got {line.get('cgst_amount')}")
            report("SGST = 0", float(line.get("sgst_amount", 0)) == 0.0,
                   f"got {line.get('sgst_amount')}")
            report("IGST rate = 18%", float(line.get("igst_rate", 0)) == 18.0,
                   f"got {line.get('igst_rate')}")
            report("IGST amount = 1800", float(line.get("igst_amount", 0)) == 1800.0,
                   f"got {line.get('igst_amount')}")
            report("Total = 11800", float(inv.get("total", 0)) == 11800.0,
                   f"got {inv.get('total')}")

    # ============================================================
    # SMOKE TEST 7: Reports (Trial Balance, P&L, Balance Sheet)
    # ============================================================
    print("\n" + "=" * 70)
    print("SMOKE TEST 7: Financial Reports")
    print("=" * 70)

    today = date.today().isoformat()
    r_tb = api("GET", f"/reports/trial-balance?as_of_date={today}", token=token_gst, tenant_id=tid_gst)
    report("Trial Balance returns 200", r_tb.status_code == 200,
           f"status={r_tb.status_code}")

    fy_start = f"{date.today().year}-04-01"
    r_pl = api("GET", f"/accounting/profit-loss?start_date={fy_start}&end_date={today}", token=token_gst, tenant_id=tid_gst)
    report("Profit & Loss returns 200", r_pl.status_code == 200,
           f"status={r_pl.status_code}")

    r_bs = api("GET", f"/reports/balance-sheet?as_of_date={today}", token=token_gst, tenant_id=tid_gst)
    report("Balance Sheet returns 200", r_bs.status_code == 200,
           f"status={r_bs.status_code}")

    # ============================================================
    # SMOKE TEST 8: GSTR-1
    # ============================================================
    print("\n" + "=" * 70)
    print("SMOKE TEST 8: GSTR-1 Report")
    print("=" * 70)

    r_gstr1 = api("GET", "/gst/gstr1", token=token_gst, tenant_id=tid_gst)
    report("GSTR-1 returns 200", r_gstr1.status_code == 200,
           f"status={r_gstr1.status_code}")

    if r_gstr1.status_code == 200:
        gstr1 = r_gstr1.json()
        b2b = gstr1.get("b2b", [])
        report("GSTR-1 B2B has entries", len(b2b) > 0,
               f"got {len(b2b)} entries")
        hsn = gstr1.get("hsn_summary", [])
        report("GSTR-1 HSN summary has entries", len(hsn) > 0,
               f"got {len(hsn)} entries")

# ============================================================
# SUMMARY
# ============================================================
print("\n" + "=" * 70)
print("SMOKE TEST SUMMARY")
print("=" * 70)
print(f"  PASSED: {PASS_COUNT}")
print(f"  FAILED: {FAIL_COUNT}")
print(f"  TOTAL:  {PASS_COUNT + FAIL_COUNT}")

if FAIL_COUNT > 0:
    print("\n  FAILED TESTS:")
    for name, status, detail in RESULTS:
        if status == "FAIL":
            print(f"    - {name}: {detail}")

print("\n" + "=" * 70)
sys.exit(0 if FAIL_COUNT == 0 else 1)
