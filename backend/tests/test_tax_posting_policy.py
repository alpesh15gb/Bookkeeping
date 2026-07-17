import uuid
from datetime import date
from decimal import Decimal

from src.domains.accounting.services import LedgerPostingEngine


def _totals(draft):
    debits = sum(
        (line.amount for line in draft.lines if line.direction == "DEBIT"),
        Decimal("0"),
    )
    credits = sum(
        (line.amount for line in draft.lines if line.direction == "CREDIT"),
        Decimal("0"),
    )
    return debits, credits


def test_invoice_shipping_is_balanced_as_revenue():
    account = uuid.uuid4()
    draft = LedgerPostingEngine.create_invoice_posting(
        tenant_id=uuid.uuid4(),
        invoice_id=uuid.uuid4(),
        invoice_number="INV-1",
        invoice_date=date.today(),
        customer_account_id=account,
        sales_revenue_account_id=account,
        subtotal=Decimal("1000"),
        shipping_charges=Decimal("100"),
        cgst_account_id=account,
        cgst_amount=Decimal("90"),
        sgst_account_id=account,
        sgst_amount=Decimal("90"),
    )
    assert _totals(draft) == (Decimal("1280"), Decimal("1280"))


def test_rcm_invoice_excludes_tax_but_keeps_shipping_balanced():
    account = uuid.uuid4()
    draft = LedgerPostingEngine.create_invoice_posting(
        tenant_id=uuid.uuid4(),
        invoice_id=uuid.uuid4(),
        invoice_number="INV-RCM",
        invoice_date=date.today(),
        customer_account_id=account,
        sales_revenue_account_id=account,
        subtotal=Decimal("1000"),
        shipping_charges=Decimal("100"),
        cgst_account_id=account,
        cgst_amount=Decimal("90"),
        sgst_account_id=account,
        sgst_amount=Decimal("90"),
        is_rcm=True,
    )
    assert _totals(draft) == (Decimal("1100"), Decimal("1100"))


def test_bill_shipping_is_balanced_as_purchase_cost():
    account = uuid.uuid4()
    draft = LedgerPostingEngine.create_bill_posting(
        tenant_id=uuid.uuid4(),
        bill_id=uuid.uuid4(),
        bill_number="BILL-1",
        bill_date=date.today(),
        vendor_account_id=account,
        purchase_expense_account_id=account,
        subtotal=Decimal("1000"),
        shipping_charges=Decimal("50"),
        igst_account_id=account,
        igst_amount=Decimal("180"),
    )
    assert _totals(draft) == (Decimal("1230"), Decimal("1230"))
