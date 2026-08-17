"""
GSTR-1 discount allocation regression.

Header discounts are stored on the invoice only (lines keep pre-discount
taxes; the invoice scales header tax by (subtotal - discount) / subtotal).
GSTR-1 and the GSTN offline-tool JSON must present per-line taxable/tax
values whose sum equals the invoice's discounted totals, otherwise a header
discount overstates taxable value and output tax in the filed return.

Regression for: /gst/gstr1 (on-screen report) and /gst/gstr1/offline-json
used to emit pre-discount line.subtotal / line tax.
"""
from datetime import date
from decimal import Decimal

from src.infrastructure.database.models import Invoice, InvoiceLine


def _posted_discounted_invoice(db_session, tenant, contact, number):
    """Invoice: 2 lines @18%/12%, 10% header discount.

    subtotal 1000, discount 100 -> taxable 900.
    Pre-discount tax 54+24=78; scaled by 0.9 -> header CGST/SGST 70.20.
    total = 900 + 70.20 + 70.20 = 1040.40
    """
    inv = Invoice(
        tenant_id=tenant.id,
        contact_id=contact.id,
        invoice_number=number,
        issue_date=date.today(),
        due_date=date.today(),
        status="POSTED",
        subtotal=Decimal("1000.0000"),
        discount_total=Decimal("100.0000"),
        cgst_amount=Decimal("70.2000"),
        sgst_amount=Decimal("70.2000"),
        igst_amount=Decimal("0.0000"),
        utgst_amount=Decimal("0.0000"),
        cess_amount=Decimal("0.0000"),
        round_off=Decimal("0.0000"),
        shipping_charges=Decimal("0.0000"),
        total=Decimal("1040.4000"),
        amount_paid=Decimal("0.0000"),
        pos_state_code="27",
        e_invoice_status="PENDING",
        supply_type="DOMESTIC",
        currency="INR",
        exchange_rate=Decimal("1"),
        tds_rate=Decimal("0"),
        tds_amount=Decimal("0"),
        tcs_rate=Decimal("0"),
        tcs_amount=Decimal("0"),
        is_rcm=False,
        is_gst_inclusive=False,
    )
    db_session.add(inv)
    db_session.flush()
    db_session.add_all([
        InvoiceLine(
            tenant_id=tenant.id, invoice_id=inv.id,
            description="Widget", quantity=Decimal("1"), rate=Decimal("600"),
            discount=Decimal("0"), subtotal=Decimal("600.0000"),
            hsn_sac="85238020", gst_rate=Decimal("18.00"),
            cgst_rate=Decimal("9.00"), cgst_amount=Decimal("54.0000"),
            sgst_rate=Decimal("9.00"), sgst_amount=Decimal("54.0000"),
            igst_rate=Decimal("0"), igst_amount=Decimal("0"),
            utgst_rate=Decimal("0"), utgst_amount=Decimal("0"),
            cess_rate=Decimal("0"), cess_amount=Decimal("0"),
            total=Decimal("708.0000"),
        ),
        InvoiceLine(
            tenant_id=tenant.id, invoice_id=inv.id,
            description="Gadget", quantity=Decimal("1"), rate=Decimal("400"),
            discount=Decimal("0"), subtotal=Decimal("400.0000"),
            hsn_sac="84713000", gst_rate=Decimal("12.00"),
            cgst_rate=Decimal("6.00"), cgst_amount=Decimal("24.0000"),
            sgst_rate=Decimal("6.00"), sgst_amount=Decimal("24.0000"),
            igst_rate=Decimal("0"), igst_amount=Decimal("0"),
            utgst_rate=Decimal("0"), utgst_amount=Decimal("0"),
            cess_rate=Decimal("0"), cess_amount=Decimal("0"),
            total=Decimal("448.0000"),
        ),
    ])
    db_session.commit()
    return inv


def test_gstr1_uses_discounted_taxable_value(client, combined_headers, contact_factory, db_session, tenant):
    contact = contact_factory(name="Discounted B2B Buyer")  # valid GSTIN -> B2B
    _posted_discounted_invoice(db_session, tenant, contact, "INV-DISC-1")
    headers = combined_headers()

    # On-screen report: B2B taxable must be subtotal - discount.
    r = client.get("/api/v1/gst/gstr1", headers=headers)
    assert r.status_code == 200, r.text
    g1 = r.json()
    assert len(g1["b2b"]) == 1
    b2b = g1["b2b"][0]
    assert float(b2b["taxable_value"]) == 900.0, b2b
    assert float(b2b["cgst_amount"]) == 70.20, b2b
    assert float(b2b["sgst_amount"]) == 70.20, b2b
    # HSN summary: per-HSN discounted taxable/tax.
    hsn = {row["hsn_sac"]: row for row in g1["hsn_summary"]}
    assert float(hsn["85238020"]["taxable_value"]) == 540.0, hsn
    assert float(hsn["85238020"]["cgst_amount"]) == 48.60, hsn
    assert float(hsn["84713000"]["taxable_value"]) == 360.0, hsn
    assert float(hsn["84713000"]["cgst_amount"]) == 21.60, hsn

    # Offline-tool JSON: per-item txval/camt/samt must match the discounted
    # allocation and sum to the invoice totals.
    r = client.get(
        "/api/v1/gst/gstr1/offline-json",
        params={"start_date": date.today().isoformat(), "end_date": date.today().isoformat()},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    payload = r.json()
    assert payload["b2b"], payload
    inv_json = payload["b2b"][0]["inv"][0]
    assert float(inv_json["val"]) == 1040.40, inv_json
    items = {item["itm_det"]["rt"]: item["itm_det"] for item in inv_json["itms"]}
    assert float(items[18]["txval"]) == 540.0, items
    assert float(items[18]["camt"]) == 48.60, items
    assert float(items[18]["samt"]) == 48.60, items
    assert float(items[12]["txval"]) == 360.0, items
    assert float(items[12]["camt"]) == 21.60, items
    assert float(items[12]["samt"]) == 21.60, items
    assert abs(sum(float(item["txval"]) for item in items.values()) - 900.0) < 0.01
    # HSN section in the file.
    hsn_json = {row["hsn_sc"]: row for row in payload["hsn"]["data"]}
    assert float(hsn_json["85238020"]["txval"]) == 540.0, hsn_json
    assert float(hsn_json["85238020"]["camt"]) == 48.60, hsn_json
    assert float(hsn_json["84713000"]["txval"]) == 360.0, hsn_json
    assert float(hsn_json["84713000"]["camt"]) == 21.60, hsn_json


def test_gstr1_unchanged_without_discount(client, combined_headers, contact_factory, db_session, tenant):
    """No discount -> the allocator must be a no-op (taxable == subtotal)."""
    contact = contact_factory(name="Full Price Buyer")
    inv = _posted_discounted_invoice(db_session, tenant, contact, "INV-FULL-1")
    inv.discount_total = Decimal("0.0000")
    inv.subtotal = Decimal("1000.0000")
    inv.total = Decimal("1156.0000")  # 1000 + 78 + 78
    inv.cgst_amount = Decimal("78.0000")
    inv.sgst_amount = Decimal("78.0000")
    db_session.commit()

    r = client.get("/api/v1/gst/gstr1", headers=combined_headers())
    assert r.status_code == 200, r.text
    b2b = r.json()["b2b"][0]
    assert float(b2b["taxable_value"]) == 1000.0, b2b
    assert float(b2b["cgst_amount"]) == 78.0, b2b
