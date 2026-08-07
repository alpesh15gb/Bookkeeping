"""Regression: GSTR-2 Excel export must classify inward bills by the SUPPLIER
state (as used at creation and by the JSON /gstr2 report), not by the company's
origin state.

An interstate purchase (vendor in state 27, company in state 36, goods received
at company so POS=36) is created and JSON-reported as IGST. The Excel
/gstr2/export must report the same IGST split — not CGST+SGST.
"""
import io
import uuid

import openpyxl
from test_premerge_verification import _register_and_login, _create_product_via_api


def _create_vendor(client, headers, name, state_code, gstin):
    body = {
        "name": name,
        "contact_type": "VENDOR",
        "state_code": state_code,
        "registration_type": "REGULAR",
        "gstin": gstin,
        "billing_address": {
            "street": "Vendor St",
            "city": "City",
            "state": "State",
            "state_code": state_code,
            "pincode": "400001",
        },
    }
    res = client.post("/api/v1/masters/contacts", json=body, headers=headers)
    assert res.status_code == 201, f"Vendor create failed: {res.status_code} {res.json()}"
    return res.json()["id"]


def _create_interstate_bill(client, headers, contact_id, product_id):
    """Vendor state 27 (Maharashtra) -> company state 36 (Telangana), POS=36."""
    res = client.post("/api/v1/bills", json={
        "bill_number": f"BILL-{uuid.uuid4().hex[:8].upper()}",
        "contact_id": contact_id,
        "issue_date": "2025-10-01",
        "due_date": "2025-11-01",
        "pos_state_code": "36",
        "line_items": [{
            "product_id": product_id,
            "description": "Interstate Purchase",
            "quantity": 1,
            "rate": 20000,
            "discount": 0,
            "hsn_sac": "998311",
            "gst_rate": 18,
        }],
    }, headers=headers)
    assert res.status_code == 201, f"Bill create failed: {res.status_code} {res.json()}"
    return res.json()


def _get_excel_row(client, headers, row_index=0):
    res = client.get("/api/v1/gst/gstr2/export", headers=headers)
    assert res.status_code == 200, f"gstr2/export failed: {res.status_code}"
    wb = openpyxl.load_workbook(io.BytesIO(res.content))
    ws = wb["b2b"]
    return [c.value for c in ws[row_index + 2]]  # skip header row


def test_gstr2_excel_reports_interstate_bill_as_igst(client):
    h, tid = _register_and_login(
        client, "gst2exp@test.com", "Gst2ExpCo",
        tax_mode="GST_REGULAR", origin_state_code="36",
    )
    pid = _create_product_via_api(client, h, "InterstateProduct", "998311", 18)
    cid = _create_vendor(
        client, h, "MH Vendor", "27",
        gstin="27AABCT1234F1Z5",
    )
    bill = _create_interstate_bill(client, h, cid, pid)
    line = bill["lines"][0]

    # The bill itself must be IGST (vendor 27 != POS 36).
    assert abs(float(line["igst_rate"]) - 18.0) < 0.001
    assert float(line["cgst_rate"]) == 0.0
    assert abs(float(line["igst_amount"]) - 3600.0) < 0.01

    # The JSON /gstr2 report must agree (reads stored IGST).
    g2 = client.get("/api/v1/gst/gstr2", headers=h).json()
    b2b = next(x for x in g2["b2b_purchases"] if x["bill_number"] == bill["bill_number"])
    assert abs(float(b2b["igst_amount"]) - 3600.0) < 0.01, b2b

    # The Excel export must ALSO report IGST, not CGST+SGST.
    row = _get_excel_row(client, h)
    # columns: gstin, name, invno, date, value, pos, rc, rate, taxable,
    #          integrated tax, central tax, state tax, cess, ...
    igst = float(row[9])
    cgst = float(row[10])
    sgst = float(row[11])
    assert abs(igst - 3600.0) < 0.01, f"Expected IGST, got row={row}"
    assert cgst == 0.0, f"Expected no CGST for interstate bill, got row={row}"
    assert sgst == 0.0, f"Expected no SGST for interstate bill, got row={row}"
