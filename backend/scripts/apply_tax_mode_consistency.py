from pathlib import Path


def replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f"{path}: expected >= {count}, found {actual}: {old[:100]!r}")
    p.write_text(text.replace(old, new, count), encoding="utf-8")


def replace_in_section(path: str, start: str, end: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    si = text.index(start)
    ei = text.index(end, si) if end else len(text)
    section = text[si:ei]
    actual = section.count(old)
    if actual < count:
        raise SystemExit(f"{path} [{start}]: expected >= {count}, found {actual}: {old[:100]!r}")
    section = section.replace(old, new, count)
    p.write_text(text[:si] + section + text[ei:], encoding="utf-8")


# ---------------------------------------------------------------------------
# Persist rate mode on recurring invoice templates.
# ---------------------------------------------------------------------------
p = "backend/src/infrastructure/database/models.py"
replace_in_section(
    p,
    "class RecurringInvoice(Base):",
    "class RecurringInvoiceItem(Base):",
    "    pos_state_code = Column(String(2), nullable=False)\n",
    "    pos_state_code = Column(String(2), nullable=False)\n    is_gst_inclusive = Column(Boolean, nullable=False, default=False)\n",
)

p = "backend/src/schemas/document.py"
replace_in_section(
    p,
    "class RecurringInvoiceCreate(SchemaBase):",
    "class RecurringInvoiceUpdate(SchemaBase):",
    "    pos_state_code: str = Field(..., pattern=\"^[0-9]{2}$\")\n",
    "    pos_state_code: str = Field(..., pattern=\"^[0-9]{2}$\")\n    is_gst_inclusive: bool\n",
)
replace_in_section(
    p,
    "class RecurringInvoiceUpdate(SchemaBase):",
    "class RecurringInvoiceResponse(SchemaBase):",
    "    pos_state_code: Optional[str] = None\n",
    "    pos_state_code: Optional[str] = None\n    is_gst_inclusive: Optional[bool] = None\n",
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
    "        pos_state_code=payload.pos_state_code,\n        is_gst_inclusive=payload.is_gst_inclusive,\n",
)
replace_in_section(
    p,
    "def list_recurring_invoices(",
    "@router.get(\"/{id}\", response_model=RecurringInvoiceResponse)",
    "            currency=r.currency,\n",
    "            currency=r.currency,\n            is_gst_inclusive=bool(r.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def generate_invoice_now(",
    "def _calculate_next_date(",
    "        line_subtotal = (item.quantity * item.rate) - item.discount\n        if line_subtotal < 0:\n            line_subtotal = Decimal(\"0.0000\")\n\n        tax_split = GSTEngine.calculate_tax(",
    "        line_subtotal = (item.quantity * item.rate) - item.discount\n        if line_subtotal < 0:\n            line_subtotal = Decimal(\"0.0000\")\n        if recurring.is_gst_inclusive and resolved_gst_rate > 0:\n            line_subtotal = line_subtotal / (\n                Decimal(\"1\") + resolved_gst_rate / Decimal(\"100\")\n            )\n\n        tax_split = GSTEngine.calculate_tax(",
)
replace_in_section(
    p,
    "def generate_invoice_now(",
    "def _calculate_next_date(",
    "        is_gst_inclusive=False,\n",
    "        is_gst_inclusive=bool(recurring.is_gst_inclusive),\n",
)

# ---------------------------------------------------------------------------
# Linked credit/debit notes inherit the source invoice's rate semantics.
# ---------------------------------------------------------------------------
p = "backend/src/api/v1/invoices.py"
for start, end in [
    ("def create_credit_note(", "@router.post(\"/credit-notes/preview\""),
    ("def preview_credit_note(", "@router.get(\"/credit-notes\""),
    ("def create_debit_note(", "@router.post(\"/debit-notes/preview\""),
    ("def preview_debit_note(", "@router.get(\"/debit-notes\""),
]:
    # Some preview functions resolve GST inline; normalize the expression first.
    text = Path(p).read_text(encoding="utf-8")
    si = text.index(start)
    ei = text.index(end, si)
    section = text[si:ei]
    inline = "gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)"
    if inline in section:
        section = section.replace(
            "        line_subtotal = (line.quantity * line.rate) - line_discount\n        tax_split = GSTEngine.calculate_tax(",
            "        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)\n        line_subtotal = (line.quantity * line.rate) - line_discount\n        if inv and inv.is_gst_inclusive and resolved_gst_rate > 0:\n            line_subtotal = line_subtotal / (Decimal(\"1\") + resolved_gst_rate / Decimal(\"100\"))\n        tax_split = GSTEngine.calculate_tax(",
            1,
        ).replace(inline, "gst_rate=resolved_gst_rate", 1)
    else:
        target = "        line_subtotal = (line.quantity * line.rate) - line_discount\n        tax_split = GSTEngine.calculate_tax("
        if target not in section:
            raise SystemExit(f"Could not find note calculation in {start}")
        section = section.replace(
            target,
            "        line_subtotal = (line.quantity * line.rate) - line_discount\n        if inv and inv.is_gst_inclusive and resolved_gst_rate > 0:\n            line_subtotal = line_subtotal / (Decimal(\"1\") + resolved_gst_rate / Decimal(\"100\"))\n        tax_split = GSTEngine.calculate_tax(",
            1,
        )
    Path(p).write_text(text[:si] + section + text[ei:], encoding="utf-8")

# Print invoice/note PDFs with explicit rate mode.
replace_in_section(
    p,
    "def print_invoice(",
    "@router.get(\"/credit-notes/{id}/print\")",
    "        place_of_supply_state_code=invoice.pos_state_code,\n",
    "        place_of_supply_state_code=invoice.pos_state_code,\n        is_gst_inclusive=bool(invoice.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def print_credit_note(",
    "@router.get(\"/debit-notes/{id}/print\")",
    "        customer_address=cn.invoice.contact.billing_address if (cn.invoice and cn.invoice.contact) else None,\n",
    "        customer_address=cn.invoice.contact.billing_address if (cn.invoice and cn.invoice.contact) else None,\n        is_gst_inclusive=bool(cn.invoice and cn.invoice.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def print_debit_note(",
    "@router.delete(\"/credit-notes/{cn_id}\"",
    "        customer_address=dn.invoice.contact.billing_address if (dn.invoice and dn.invoice.contact) else None,\n",
    "        customer_address=dn.invoice.contact.billing_address if (dn.invoice and dn.invoice.contact) else None,\n        is_gst_inclusive=bool(dn.invoice and dn.invoice.is_gst_inclusive),\n",
)

# Clone all tax semantics, not just precomputed amounts.
replace_in_section(
    p,
    "def clone_invoice(",
    "class EmailInvoiceRequest(BaseModel):",
    "        pos_state_code=original.pos_state_code,\n",
    "        pos_state_code=original.pos_state_code,\n        is_gst_inclusive=bool(original.is_gst_inclusive),\n        is_rcm=bool(original.is_rcm),\n        supply_type=original.supply_type,\n        currency=original.currency,\n        exchange_rate=original.exchange_rate,\n        tds_rate=original.tds_rate,\n        tds_amount=original.tds_amount,\n        tcs_rate=original.tcs_rate,\n        tcs_amount=original.tcs_amount,\n",
)

# Purchase bill print/clone must preserve the same flag.
p = "backend/src/api/v1/bills.py"
replace_in_section(
    p,
    "def print_bill(",
    "@router.post(\"/{id}/clone\"",
    "        terms_and_conditions=bill.terms_and_conditions,\n",
    "        terms_and_conditions=bill.terms_and_conditions,\n        is_gst_inclusive=bool(bill.is_gst_inclusive),\n",
)
replace_in_section(
    p,
    "def clone_bill(",
    "",  # to EOF
    "        pos_state_code=original.pos_state_code,\n",
    "        pos_state_code=original.pos_state_code,\n        is_gst_inclusive=bool(original.is_gst_inclusive),\n",
)

# ---------------------------------------------------------------------------
# PDF: every template says whether displayed input rates already include GST.
# ---------------------------------------------------------------------------
p = "backend/src/domains/printing/invoice_pdf.py"
replace(
    p,
    "    place_of_supply_state_code: Optional[str] = None,\n) -> bytes:",
    "    place_of_supply_state_code: Optional[str] = None,\n    is_gst_inclusive: bool = False,\n) -> bytes:",
)
replace(
    p,
    "    display_pos_code = place_of_supply_state_code or origin_state_code\n",
    "    display_pos_code = place_of_supply_state_code or origin_state_code\n    rate_header = \"Rate (Incl. GST)\" if is_gst_inclusive else \"Rate (Excl. GST)\"\n    rate_mode_note = (\n        \"GST inclusive: displayed rates already contain GST; tax is extracted from the rate.\"\n        if is_gst_inclusive\n        else \"GST exclusive: displayed rates are taxable values; GST is added on top.\"\n    )\n",
)
replace(p, "            Paragraph(\"<b>Rate</b>\", right_style),", "            Paragraph(f\"<b>{rate_header}</b>\", right_style),")
replace(p, "        table_headers = ['S.No.', 'Description of Goods', 'Qty', 'Rate', 'Amount']", "        table_headers = ['S.No.', 'Description of Goods', 'Qty', rate_header, 'Amount']")
replace(p, "        table_headers = ['S.No.', 'Description', 'Qty', 'Rate', 'Amount']", "        table_headers = ['S.No.', 'Description', 'Qty', rate_header, 'Amount']")
replace(p, "            Paragraph(\"<b>Price/ Unit</b>\", ParagraphStyle('ColH5', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),", "            Paragraph(f\"<b>{rate_header}</b>\", ParagraphStyle('ColH5', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),")
# A visible mode note immediately before item tables works across all templates.
replace(
    p,
    "    # Render Thermal / POS Layout\n",
    "    # Explicit rate semantics prevent inclusive prices being mistaken for taxable rates.\n    rate_mode_paragraph = Paragraph(rate_mode_note, caption_style)\n\n    # Render Thermal / POS Layout\n",
)
# Add the note once in each major layout before its items table/metadata.
replace(p, "        elements.append(Spacer(1, 2*mm))\n        \n        # Table columns", "        elements.append(Spacer(1, 2*mm))\n        elements.append(rate_mode_paragraph)\n        elements.append(Spacer(1, 1*mm))\n        \n        # Table columns")
replace(p, "        elements.append(billing_table)\n        elements.append(Spacer(1, 4*mm))\n\n        # Items Table", "        elements.append(billing_table)\n        elements.append(Spacer(1, 2*mm))\n        elements.append(rate_mode_paragraph)\n        elements.append(Spacer(1, 2*mm))\n\n        # Items Table")
replace(p, "        elements.append(bill_to_table)\n        \n        # Items Table", "        elements.append(bill_to_table)\n        elements.append(Spacer(1, 2*mm))\n        elements.append(rate_mode_paragraph)\n        elements.append(Spacer(1, 2*mm))\n        \n        # Items Table")
replace(p, "        elements.append(Spacer(1, 4*mm))\n        \n        # Classic Items Table.", "        elements.append(Spacer(1, 2*mm))\n        elements.append(rate_mode_paragraph)\n        elements.append(Spacer(1, 2*mm))\n        \n        # Classic Items Table.")

# ---------------------------------------------------------------------------
# Migration for recurring template tax mode.
# ---------------------------------------------------------------------------
migration = Path("backend/alembic/versions/20260821_0001_recurring_invoice_tax_mode.py")
if not migration.exists():
    migration.write_text('''"""persist GST-inclusive rate mode on recurring invoice templates

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
''', encoding="utf-8")

# ---------------------------------------------------------------------------
# Regression tests that do not require live external services.
# ---------------------------------------------------------------------------
test = Path("backend/tests/test_tax_mode_contract.py")
test.write_text('''from decimal import Decimal\n\nfrom src.schemas.document import RecurringInvoiceCreate\n\n\ndef test_recurring_invoice_requires_explicit_tax_mode():\n    payload = RecurringInvoiceCreate(\n        contact_id="00000000-0000-0000-0000-000000000001",\n        template_name="Inclusive rent",\n        frequency="MONTHLY",\n        interval_count=1,\n        next_date="2026-09-01",\n        end_mode="NEVER",\n        currency="INR",\n        exchange_rate=Decimal("1"),\n        pos_state_code="27",\n        is_gst_inclusive=True,\n        items=[{\n            "product_id": "00000000-0000-0000-0000-000000000002",\n            "quantity": Decimal("1"),\n            "rate": Decimal("16500"),\n            "discount": Decimal("0"),\n            "hsn_sac": "998311",\n            "gst_rate": Decimal("18"),\n        }],\n    )\n    assert payload.is_gst_inclusive is True\n\n\ndef test_inclusive_16500_extracts_18_percent_gst():\n    gross = Decimal("16500")\n    rate = Decimal("18")\n    taxable = gross / (Decimal("1") + rate / Decimal("100"))\n    gst = gross - taxable\n    assert taxable.quantize(Decimal("0.01")) == Decimal("13983.05")\n    assert gst.quantize(Decimal("0.01")) == Decimal("2516.95")\n    assert (taxable + gst).quantize(Decimal("0.01")) == Decimal("16500.00")\n''', encoding="utf-8")

print("Backend tax-mode consistency codemod applied successfully.")
