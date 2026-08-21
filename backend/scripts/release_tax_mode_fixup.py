from pathlib import Path


def replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f"{path}: expected >= {count}, found {actual}: {old[:120]!r}")
    p.write_text(text.replace(old, new, count), encoding="utf-8")


def replace_in_section(path: str, start: str, end: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    si = text.index(start)
    ei = text.index(end, si) if end else len(text)
    section = text[si:ei]
    actual = section.count(old)
    if actual < count:
        raise SystemExit(
            f"{path} [{start}]: expected >= {count}, found {actual}: {old[:120]!r}"
        )
    section = section.replace(old, new, count)
    p.write_text(text[:si] + section + text[ei:], encoding="utf-8")


# ---------------------------------------------------------------------------
# Recurring invoice templates persist the same explicit rate semantics as a
# normal invoice. Existing/API integrations remain backward-compatible: false
# is the default, while the Flutter UI requires an explicit choice.
# ---------------------------------------------------------------------------
p = "backend/src/infrastructure/database/models.py"
replace_in_section(
    p,
    "class RecurringInvoice(Base):",
    "class RecurringInvoiceItem(Base):",
    "    pos_state_code = Column(String(2), nullable=False)\n",
    "    pos_state_code = Column(String(2), nullable=False)\n"
    "    is_gst_inclusive = Column(Boolean, nullable=False, default=False)\n",
)

p = "backend/src/schemas/document.py"
replace_in_section(
    p,
    "class RecurringInvoiceCreate(SchemaBase):",
    "class RecurringInvoiceUpdate(SchemaBase):",
    "    pos_state_code: str = Field(..., pattern=\"^[0-9]{2}$\")\n",
    "    pos_state_code: str = Field(..., pattern=\"^[0-9]{2}$\")\n"
    "    is_gst_inclusive: bool = False\n",
)
replace_in_section(
    p,
    "class RecurringInvoiceUpdate(SchemaBase):",
    "class RecurringInvoiceResponse(SchemaBase):",
    "    pos_state_code: Optional[str] = None\n",
    "    pos_state_code: Optional[str] = None\n"
    "    is_gst_inclusive: Optional[bool] = None\n",
)
replace_in_section(
    p,
    "class RecurringInvoiceResponse(SchemaBase):",
    "class RecurringInvoiceListResponse(SchemaBase):",
    "    pos_state_code: str\n",
    "    pos_state_code: str\n    is_gst_inclusive: bool\n",
)
replace_in_section(
    p,
    "class RecurringInvoiceListResponse(SchemaBase):",
    "# ── TERMS TEMPLATE SCHEMAS",
    "    currency: str\n",
    "    currency: str\n    is_gst_inclusive: bool\n",
)

p = "backend/src/api/v1/recurring_invoices.py"
replace_in_section(
    p,
    "def create_recurring_invoice(",
    "@router.get(\"\", response_model=List[RecurringInvoiceListResponse])",
    "        pos_state_code=payload.pos_state_code,\n",
    "        pos_state_code=payload.pos_state_code,\n"
    "        is_gst_inclusive=payload.is_gst_inclusive,\n",
)
replace_in_section(
    p,
    "def list_recurring_invoices(",
    "@router.get(\"/{id}\", response_model=RecurringInvoiceResponse)",
    "            currency=r.currency,\n",
    "            currency=r.currency,\n"
    "            is_gst_inclusive=bool(r.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def generate_invoice_now(",
    "def _calculate_next_date(",
    "        line_subtotal = (item.quantity * item.rate) - item.discount\n"
    "        if line_subtotal < 0:\n"
    "            line_subtotal = Decimal(\"0.0000\")\n\n"
    "        tax_split = GSTEngine.calculate_tax(",
    "        line_subtotal = (item.quantity * item.rate) - item.discount\n"
    "        if line_subtotal < 0:\n"
    "            line_subtotal = Decimal(\"0.0000\")\n"
    "        if recurring.is_gst_inclusive and resolved_gst_rate > 0:\n"
    "            line_subtotal = line_subtotal / (\n"
    "                Decimal(\"1\") + resolved_gst_rate / Decimal(\"100\")\n"
    "            )\n\n"
    "        tax_split = GSTEngine.calculate_tax(",
)
replace_in_section(
    p,
    "def generate_invoice_now(",
    "def _calculate_next_date(",
    "        is_gst_inclusive=False,\n",
    "        is_gst_inclusive=bool(recurring.is_gst_inclusive),\n",
)

# ---------------------------------------------------------------------------
# Clone fidelity: clones must preserve every tax-affecting semantic field.
# Credit/debit notes are intentionally NOT changed here: their stored rate is
# a taxable/exclusive rate, and the Flutter editor already normalizes a linked
# inclusive source line before sending it.
# ---------------------------------------------------------------------------
p = "backend/src/api/v1/invoices.py"
replace_in_section(
    p,
    "def print_invoice(",
    "@router.get(\"/credit-notes/{id}/print\")",
    "        place_of_supply_state_code=invoice.pos_state_code,\n",
    "        place_of_supply_state_code=invoice.pos_state_code,\n"
    "        is_gst_inclusive=bool(invoice.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def clone_invoice(",
    "class EmailInvoiceRequest(BaseModel):",
    "        pos_state_code=original.pos_state_code,\n",
    "        pos_state_code=original.pos_state_code,\n"
    "        is_gst_inclusive=bool(original.is_gst_inclusive),\n"
    "        is_rcm=bool(original.is_rcm),\n"
    "        supply_type=original.supply_type,\n"
    "        currency=original.currency,\n"
    "        exchange_rate=original.exchange_rate,\n"
    "        tds_rate=original.tds_rate,\n"
    "        tds_amount=original.tds_amount,\n"
    "        tcs_rate=original.tcs_rate,\n"
    "        tcs_amount=original.tcs_amount,\n",
)

p = "backend/src/api/v1/bills.py"
replace_in_section(
    p,
    "def print_bill(",
    "@router.post(\"/{id}/clone\"",
    "        terms_and_conditions=bill.terms_and_conditions,\n",
    "        terms_and_conditions=bill.terms_and_conditions,\n"
    "        is_gst_inclusive=bool(bill.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def clone_bill(",
    "",
    "        pos_state_code=original.pos_state_code,\n",
    "        pos_state_code=original.pos_state_code,\n"
    "        shipping_charges=original.shipping_charges,\n"
    "        is_gst_inclusive=bool(original.is_gst_inclusive),\n"
    "        itc_eligible=bool(original.itc_eligible),\n",
)

# ---------------------------------------------------------------------------
# Printed documents state rate semantics in the column heading. Other document
# types use the backward-compatible default (exclusive) unless explicitly
# passed by invoice/bill printing routes.
# ---------------------------------------------------------------------------
p = "backend/src/domains/printing/invoice_pdf.py"
replace(
    p,
    "    place_of_supply_state_code: Optional[str] = None,\n) -> bytes:",
    "    place_of_supply_state_code: Optional[str] = None,\n"
    "    is_gst_inclusive: bool = False,\n"
    ") -> bytes:",
)
replace(
    p,
    "    display_pos_code = place_of_supply_state_code or origin_state_code\n",
    "    display_pos_code = place_of_supply_state_code or origin_state_code\n"
    "    rate_header = (\n"
    "        \"Rate incl. GST\" if is_gst_inclusive else \"Rate excl. GST\"\n"
    "    )\n",
)
replace(
    p,
    "            Paragraph(\"<b>Rate</b>\", right_style),",
    "            Paragraph(f\"<b>{rate_header}</b>\", right_style),",
)
replace(
    p,
    "        table_headers = ['S.No.', 'Description of Goods', 'Qty', 'Rate', 'Amount']",
    "        table_headers = ['S.No.', 'Description of Goods', 'Qty', rate_header, 'Amount']",
)
replace(
    p,
    "            Paragraph(\"<b>Price/ Unit</b>\", ParagraphStyle('ColH5', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),",
    "            Paragraph(f\"<b>{rate_header}</b>\", ParagraphStyle('ColH5', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),",
)
replace(
    p,
    "        table_headers = ['S.No.', 'Description', 'Qty', 'Rate', 'Amount']",
    "        table_headers = ['S.No.', 'Description', 'Qty', rate_header, 'Amount']",
)

# ---------------------------------------------------------------------------
# Alembic + readiness contract.
# ---------------------------------------------------------------------------
revision = "20260821_0001_recurring_invoice_tax_mode"
migration = Path(
    f"backend/alembic/versions/{revision}.py"
)
if migration.exists():
    raise SystemExit(f"Migration already exists unexpectedly: {migration}")
migration.write_text(
    '''"""persist GST-inclusive rate mode on recurring invoice templates

Revision ID: 20260821_0001_recurring_invoice_tax_mode
Revises: 20260818_0004_super_admin_subscriptions
Create Date: 2026-08-21
"""
from alembic import op
import sqlalchemy as sa

revision = "20260821_0001_recurring_invoice_tax_mode"
down_revision = "20260818_0004_super_admin_subscriptions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "recurring_invoices",
        sa.Column(
            "is_gst_inclusive",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade() -> None:
    op.drop_column("recurring_invoices", "is_gst_inclusive")
''',
    encoding="utf-8",
)

p = "backend/src/main.py"
replace(
    p,
    'REQUIRED_SCHEMA_REVISION = "20260818_0004_super_admin_subscriptions"',
    f'REQUIRED_SCHEMA_REVISION = "{revision}"',
)

# ---------------------------------------------------------------------------
# Regression contracts.
# ---------------------------------------------------------------------------
test = Path("backend/tests/test_tax_mode_contract.py")
test.write_text(
    r'''from decimal import Decimal
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
''',
    encoding="utf-8",
)

print("Backend release GST fixup applied.")
