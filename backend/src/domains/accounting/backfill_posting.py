"""
State-preserving ledger posting for imported documents.

The legacy importers (Vyapar/Tally) create documents in their final statuses
(POSTED/PARTIALLY_PAID/PAID) with amounts-paid and stock already reflected.
Posting those documents must therefore create the *missing journal entries*
without touching document status, amount_paid, allocations or stock — the
ledger is a projection of the documents, never the other way round.

These helpers are used both at import time (so new imports land in the books)
and by POST /api/v1/import/backfill-postings (to repair tenants imported
before this logic existed).  Every helper is idempotent: re-running never
double-posts (see ``_check_no_existing_posting``).
"""
from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy.orm import Session

from src.domains.accounting.auto_post import (
    _check_no_existing_posting,
    _resolve_tax_accounts,
)
from src.domains.accounting.services import (
    AccountResolver,
    LedgerPostingEngine,
    commit_ledger_draft,
)
from src.infrastructure.database.models import (
    Bill,
    BillPayment,
    Expense,
    ExpenseCategory,
    Invoice,
    Payment,
)


def _asset_account_key(payment_mode: str) -> str:
    """Map bank instruments to the bank ledger (mirrors payments.py).

    Imported modes arrive uppercase (BANK, CASH, …) while the chart keys are
    lowercase; unknown/legacy modes fall back to cash so a payment is never
    silently dropped from the ledger.
    """
    mode = (payment_mode or "").lower()
    if mode in {"cheque", "neft_rtgs"}:
        return "bank"
    return mode if mode in {"cash", "bank", "upi", "pos"} else "cash"


def _residual_round_off(total, subtotal, discount_total, shipping_charges,
                        cgst, sgst, igst, utgst, cess) -> Decimal:
    """Round-off that reconciles the posted lines to the document total, in paise."""
    from decimal import ROUND_HALF_UP

    tax_total = (cgst or Decimal("0")) + (sgst or Decimal("0")) + (igst or Decimal("0")) \
        + (utgst or Decimal("0")) + (cess or Decimal("0"))
    computed = (subtotal or Decimal("0")) - (discount_total or Decimal("0")) \
        + (shipping_charges or Decimal("0")) + tax_total
    residual = (total or Decimal("0")) - computed
    return residual.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _disambiguate_reference(db: Session, tenant_id: uuid.UUID, draft, doc_id: uuid.UUID) -> None:
    """Legacy imports can repeat document numbers (the ledger enforces a unique
    reference per tenant).  When the plain reference would collide with an
    existing journal entry, append the document id so the posting still lands."""
    from src.infrastructure.database.models import JournalEntry

    existing = db.query(JournalEntry.id).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.reference_number == draft.reference_number,
    ).first()
    if existing:
        draft.reference_number = f"{draft.reference_number}~{str(doc_id)[:8]}"


def post_invoice_if_missing(db: Session, tenant_id: uuid.UUID, invoice: Invoice) -> bool:
    """Create the journal entry for an invoice if one does not exist. Returns True if posted."""
    if invoice.total is None or invoice.total <= 0:
        raise ValueError("cannot post invoice with non-positive total (likely a credit note imported as an invoice)")
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")
    _check_no_existing_posting(db, tenant_id, "INVOICE", invoice.id)
    # Recompute round-off from the document totals: legacy imports keep
    # sub-paisa dust (e.g. 0.0024) which the ledger quantizes to 0.00 lines
    # (invalid: amount > 0).  The real residual against the document total is
    # what round-off must reconcile, in paise.
    round_off = _residual_round_off(invoice.total, invoice.subtotal, invoice.discount_total,
                                    invoice.shipping_charges, invoice.cgst_amount, invoice.sgst_amount,
                                    invoice.igst_amount, invoice.utgst_amount, invoice.cess_amount)
    draft = LedgerPostingEngine.create_invoice_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        invoice_date=invoice.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
        shipping_charges=invoice.shipping_charges or Decimal("0.0000"),
        cgst_account_id=tax["cgst"],
        cgst_amount=invoice.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=invoice.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=invoice.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=invoice.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=invoice.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=round_off,
        is_rcm=invoice.is_rcm,
        tds_account_id=resolver.resolve("tds_receivable") if invoice.tds_amount and invoice.tds_amount > 0 else None,
        tds_amount=invoice.tds_amount or Decimal("0"),
        tcs_account_id=resolver.resolve("liability.tcs") if invoice.tcs_amount and invoice.tcs_amount > 0 else None,
        tcs_amount=invoice.tcs_amount or Decimal("0"),
    )
    _disambiguate_reference(db, tenant_id, draft, invoice.id)
    commit_ledger_draft(db, tenant_id, draft)
    return True


def post_bill_if_missing(db: Session, tenant_id: uuid.UUID, bill: Bill) -> bool:
    """Create the journal entry for a bill if one does not exist. Returns True if posted."""
    if bill.total is None or bill.total <= 0:
        raise ValueError("cannot post bill with non-positive total (likely a debit note imported as a bill)")
    _check_no_existing_posting(db, tenant_id, "BILL", bill.id)
    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    tax = _resolve_tax_accounts(resolver, "input")
    tds_account_id = resolver.resolve("liability.tds") if bill.tds_amount and bill.tds_amount > 0 else None
    tax_total = bill.cgst_amount + bill.sgst_amount + bill.igst_amount + bill.utgst_amount + bill.cess_amount
    posting_subtotal = bill.subtotal if bill.itc_eligible else bill.subtotal + tax_total
    round_off = _residual_round_off(bill.total, bill.subtotal, bill.discount_total,
                                    bill.shipping_charges, bill.cgst_amount, bill.sgst_amount,
                                    bill.igst_amount, bill.utgst_amount, bill.cess_amount)
    draft = LedgerPostingEngine.create_bill_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        bill_date=bill.issue_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=posting_subtotal,
        discount_total=bill.discount_total,
        shipping_charges=bill.shipping_charges or Decimal("0"),
        cgst_account_id=tax["cgst"],
        cgst_amount=bill.cgst_amount if bill.itc_eligible else Decimal("0"),
        sgst_account_id=tax["sgst"],
        sgst_amount=bill.sgst_amount if bill.itc_eligible else Decimal("0"),
        igst_account_id=tax["igst"],
        igst_amount=bill.igst_amount if bill.itc_eligible else Decimal("0"),
        utgst_account_id=tax["utgst"],
        utgst_amount=bill.utgst_amount if bill.itc_eligible else Decimal("0"),
        cess_account_id=tax["cess"],
        cess_amount=bill.cess_amount if bill.itc_eligible else Decimal("0"),
        round_off_account_id=tax["round_off"],
        round_off_amount=round_off,
        tds_account_id=tds_account_id,
        tds_amount=bill.tds_amount or Decimal("0"),
    )
    _disambiguate_reference(db, tenant_id, draft, bill.id)
    commit_ledger_draft(db, tenant_id, draft)
    return True


def post_payment_if_missing(db: Session, tenant_id: uuid.UUID, payment: Payment) -> bool:
    """Create the customer-payment journal entry if one does not exist. Returns True if posted."""
    if payment.amount is None or payment.amount <= 0:
        raise ValueError("cannot post payment with non-positive amount")
    _check_no_existing_posting(db, tenant_id, "PAYMENT", payment.id)
    resolver = AccountResolver(db, tenant_id)
    bank_or_cash = resolver.resolve(f"assets.{_asset_account_key(payment.payment_mode)}")
    customer = resolver.resolve(f"customer.{payment.contact_id}")
    draft = LedgerPostingEngine.create_payment_receipt_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        payment_date=payment.payment_date,
        bank_or_cash_account_id=bank_or_cash,
        customer_account_id=customer,
        amount=payment.amount,
    )
    commit_ledger_draft(db, tenant_id, draft)
    return True


def post_expense_if_missing(db: Session, tenant_id: uuid.UUID, expense: Expense) -> bool:
    """Create the expense journal entry if one does not exist. Returns True if posted.

    Mirrors the interactive expense post flow (expenses.py) so imported
    POSTED expenses land in the books the same way hand-entered ones do.
    """
    if expense.amount is None or expense.amount <= 0:
        raise ValueError("cannot post expense with non-positive amount")
    _check_no_existing_posting(db, tenant_id, "EXPENSE", expense.id)
    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.deleted_at.is_(None),
    ).first()
    if not category or not category.linked_account_id:
        raise ValueError(f"Expense {expense.expense_number} has no linked account to post.")
    from src.domains.taxation.services import GSTEngine

    resolver = AccountResolver(db, tenant_id)
    cash_account_id = expense.bank_account_id or resolver.resolve("assets.cash")
    cgst_input_id = resolver.resolve("cgst_input")
    sgst_input_id = resolver.resolve("sgst_input")
    igst_input_id = resolver.resolve("igst_input")
    utgst_input_id = resolver.resolve("utgst_input")
    cess_input_id = resolver.resolve("cess_input")
    round_off_account_id = resolver.resolve("round_off") if (expense.round_off or 0) != 0 else None
    claim_itc = GSTEngine.can_claim_itc(db, tenant_id, True)
    tax_total = (
        (expense.cgst_amount or 0) + (expense.sgst_amount or 0) + (expense.igst_amount or 0)
        + (expense.utgst_amount or 0) + (expense.cess_amount or 0)
    )
    draft = LedgerPostingEngine.create_expense_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        expense_date=expense.expense_date,
        expense_account_id=category.linked_account_id,
        cash_account_id=cash_account_id,
        amount=expense.amount if claim_itc else expense.amount + tax_total,
        cgst_account_id=cgst_input_id,
        cgst_amount=expense.cgst_amount if claim_itc else Decimal("0"),
        sgst_account_id=sgst_input_id,
        sgst_amount=expense.sgst_amount if claim_itc else Decimal("0"),
        igst_account_id=igst_input_id,
        igst_amount=expense.igst_amount if claim_itc else Decimal("0"),
        utgst_account_id=utgst_input_id,
        utgst_amount=expense.utgst_amount if claim_itc else Decimal("0"),
        cess_account_id=cess_input_id,
        cess_amount=expense.cess_amount if claim_itc else Decimal("0"),
        round_off_account_id=round_off_account_id,
        round_off_amount=expense.round_off or Decimal("0"),
    )
    commit_ledger_draft(db, tenant_id, draft)
    return True


def post_bill_payment_if_missing(db: Session, tenant_id: uuid.UUID, bp: BillPayment) -> bool:
    """Create the vendor-payment journal entry if one does not exist. Returns True if posted."""
    if bp.amount is None or bp.amount <= 0:
        raise ValueError("cannot post payment with non-positive amount")
    _check_no_existing_posting(db, tenant_id, "PAYMENT", bp.id)
    resolver = AccountResolver(db, tenant_id)
    bank_or_cash = resolver.resolve(f"assets.{_asset_account_key(bp.payment_mode)}")
    vendor = resolver.resolve(f"vendor.{bp.contact_id}")
    draft = LedgerPostingEngine.create_payment_out_posting(
        tenant_id=tenant_id,
        payment_id=bp.id,
        payment_number=bp.payment_number,
        payment_date=bp.payment_date,
        bank_or_cash_account_id=bank_or_cash,
        vendor_account_id=vendor,
        amount=bp.amount,
    )
    commit_ledger_draft(db, tenant_id, draft)
    return True
