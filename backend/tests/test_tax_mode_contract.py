from decimal import Decimal
from pathlib import Path

from src.schemas.document import RecurringInvoiceCreate


def test_recurring_invoice_accepts_explicit_inclusive_rate_mode():
    payload = RecurringInvoiceCreate(
        contact_id="00000000-0000-0000-0000-000000000001",
        template_name="Inclusive rent",
        frequency="MONTHLY",
        interval_count=1,
        next_date="2026-09-01",
        end_mode="NEVER",
        currency="INR",
        exchange_rate=Decimal("1"),
        pos_state_code="27",
        is_gst_inclusive=True,
        items=[{
            "product_id": "00000000-0000-0000-0000-000000000002",
            "quantity": Decimal("1"),
            "rate": Decimal("16500"),
            "discount": Decimal("0"),
            "hsn_sac": "998311",
            "gst_rate": Decimal("18"),
        }],
    )
    assert payload.is_gst_inclusive is True


def test_recurring_invoice_keeps_backward_compatible_exclusive_default():
    payload = RecurringInvoiceCreate(
        contact_id="00000000-0000-0000-0000-000000000001",
        template_name="Legacy template",
        next_date="2026-09-01",
        pos_state_code="27",
        items=[{
            "product_id": "00000000-0000-0000-0000-000000000002",
            "quantity": Decimal("1"),
            "rate": Decimal("100"),
            "hsn_sac": "998311",
            "gst_rate": Decimal("18"),
        }],
    )
    assert payload.is_gst_inclusive is False


def test_inclusive_16500_extracts_18_percent_gst_without_increasing_total():
    gross = Decimal("16500")
    rate = Decimal("18")
    taxable = gross / (Decimal("1") + rate / Decimal("100"))
    gst = gross - taxable
    assert taxable.quantize(Decimal("0.01")) == Decimal("13983.05")
    assert gst.quantize(Decimal("0.01")) == Decimal("2516.95")
    assert (taxable + gst).quantize(Decimal("0.01")) == Decimal("16500.00")


def test_clone_and_pdf_contracts_preserve_rate_semantics():
    invoices = Path("src/api/v1/invoices.py").read_text(encoding="utf-8")
    bills = Path("src/api/v1/bills.py").read_text(encoding="utf-8")
    pdf = Path("src/domains/printing/invoice_pdf.py").read_text(encoding="utf-8")

    invoice_clone = invoices[invoices.index("def clone_invoice("):]
    assert "is_gst_inclusive=bool(original.is_gst_inclusive)" in invoice_clone
    assert "supply_type=original.supply_type" in invoice_clone
    assert "tds_rate=original.tds_rate" in invoice_clone
    assert "tcs_rate=original.tcs_rate" in invoice_clone

    bill_clone = bills[bills.index("def clone_bill("):]
    assert "is_gst_inclusive=bool(original.is_gst_inclusive)" in bill_clone
    assert "shipping_charges=original.shipping_charges" in bill_clone
    assert "itc_eligible=bool(original.itc_eligible)" in bill_clone

    assert "Rate incl. GST" in pdf
    assert "Rate excl. GST" in pdf
