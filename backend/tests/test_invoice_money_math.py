import uuid
from datetime import date
from decimal import Decimal

from src.infrastructure.database.models import JournalEntry, JournalLine, Invoice


def _payload(contact_id, product_id, **overrides):
    payload = {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-MM-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "line_items": [{
            "product_id": str(product_id),
            "quantity": 10,
            "rate": 100,
            "discount": 0,
            "hsn_sac": "9983",
            "gst_rate": 18,
        }],
    }
    payload.update(overrides)
    return payload


def test_header_discount_rewrites_line_taxes_and_freight_is_taxed(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """H1 + H4: a header discount must be allocated across lines (persisted
    line taxes agree with the header), and freight must be part of the taxable
    base rather than appended untaxed after tax."""
    tenant.tax_mode = "GST_REGULAR"
    db_session.commit()
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"), gst_rate=Decimal("18"))
    created = client.post(
        "/api/v1/invoices",
        json=_payload(contact.id, product.id, discount_rate=10, shipping_charges=50),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    data = created.json()

    inv = db_session.query(Invoice).filter(Invoice.id == uuid.UUID(data["id"])).one()

    # 10 items x 100 = 1000 subtotal; 10% header discount = 100.
    # Freight 50 is taxed: taxable base = 1000 - 100 + 50 = 950. 18% on 950
    # = 171 total tax (CGST+SGST intra-state, or IGST inter-state depending on
    # the tenant's registered origin state).
    tax_total = (Decimal(inv.cgst_amount) + Decimal(inv.sgst_amount)
                 + Decimal(inv.igst_amount) + Decimal(inv.utgst_amount)
                 + Decimal(inv.cess_amount))
    assert Decimal(inv.subtotal) == Decimal("1000.00")
    assert Decimal(inv.discount_total) == Decimal("100.00")
    assert Decimal(inv.shipping_charges) == Decimal("50.00")
    assert tax_total == Decimal("171.00")
    assert Decimal(inv.total) == Decimal("950.00") + Decimal("171.00")

    # Persisted lines must carry the discounted taxable and agree with the header.
    line = inv.lines[0]
    assert Decimal(line.subtotal) == Decimal("950.00")  # 1000 discounted + 50 freight
    line_tax = (Decimal(line.cgst_amount or 0) + Decimal(line.sgst_amount or 0)
                + Decimal(line.igst_amount or 0) + Decimal(line.utgst_amount or 0)
                + Decimal(line.cess_amount or 0))
    assert line_tax == Decimal("171.00")
    # Line total = taxable + tax
    assert Decimal(line.total) == Decimal("950.00") + Decimal("171.00")
    # Header == sum of lines for every tax bucket
    for bucket in ("cgst", "sgst", "igst", "utgst", "cess"):
        line_sum = sum(Decimal(getattr(l, f"{bucket}_amount") or 0) for l in inv.lines)
        assert line_sum == Decimal(getattr(inv, f"{bucket}_amount")), bucket


def test_invoice_totals_round_to_paise_not_whole_rupees(
    client, combined_headers, tenant, db_session, contact_factory, product_factory,
):
    """H2: payable rounds to paise (0.01), never ±0.50 to a whole rupee."""
    tenant.tax_mode = "GST_REGULAR"
    db_session.commit()
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"), gst_rate=Decimal("18"))
    created = client.post(
        "/api/v1/invoices",
        json=_payload(contact.id, product.id, line_items=[{
            "product_id": str(product.id),
            "quantity": 3,
            "rate": 99.99,
            "discount": 0,
            "hsn_sac": "9983",
            "gst_rate": 18,
        }]),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    total = Decimal(created.json()["total"])
    assert total == total.quantize(Decimal("0.01"))


def test_sales_tds_and_tcs_are_posted_to_ledger(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """H3: sales TDS/TCS must land in the journal (TDS receivable asset,
    TCS payable liability) instead of being stored and never posted."""
    tenant.tax_mode = "GST_REGULAR"
    db_session.commit()
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"), gst_rate=Decimal("18"))
    created = client.post(
        "/api/v1/invoices",
        json=_payload(contact.id, product.id, tds_rate=2, tcs_rate=0.1),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    data = created.json()
    assert Decimal(data["tds_amount"]) > 0
    assert Decimal(data["tcs_amount"]) > 0
    invoice_id = uuid.UUID(data["id"])

    entry = db_session.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant.id,
        JournalEntry.source_type == "INVOICE",
        JournalEntry.source_id == invoice_id,
    ).one()

    tds_lines = [l for l in entry.lines if "TDS" in (l.narration or "")]
    tcs_lines = [l for l in entry.lines if "TCS" in (l.narration or "")]
    assert len(tds_lines) == 1 and tds_lines[0].direction == "DEBIT"
    assert len(tcs_lines) == 1 and tcs_lines[0].direction == "CREDIT"

    debits = sum((l.amount for l in entry.lines if l.direction == "DEBIT"), Decimal("0"))
    credits = sum((l.amount for l in entry.lines if l.direction == "CREDIT"), Decimal("0"))
    assert debits == credits
