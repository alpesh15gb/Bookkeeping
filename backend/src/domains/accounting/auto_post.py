"""
Auto-posting service for financial documents.

When a document is created, this module:
1. Persists the document with POSTED status (or business status)
2. Creates the journal entry via LedgerPostingEngine
3. Commits to the ledger in real-time

When a document is cancelled:
1. Creates reversing journal entries
2. Sets CANCELLED status

This removes the manual DRAFT -> POSTED step for all financial documents.
"""
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from sqlalchemy.orm import Session

from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Bill, BillLine, Expense, CreditNote, DebitNote,
    SalesReturn, SalesReturnLine, PurchaseReturn, PurchaseReturnLine,
    JournalEntry, Account, Contact, TenantMembership, StockLedger, Product,
)
from src.domains.accounting.services import (
    LedgerPostingEngine, JournalEntryDraft, commit_ledger_draft, AccountResolver,
)
from src.common.audit_log import set_audit_context


# --- Status Mapping -------------------------------------------------------

def get_display_status(invoice: Invoice) -> str:
    """Map Invoice internal status to visible business status."""
    if invoice.status == "CANCELLED":
        return "Cancelled"
    if invoice.status == "DRAFT":
        return "Draft"
    if invoice.status == "PAID":
        return "Paid"
    if invoice.status == "PARTIALLY_PAID":
        return "Partially Paid"
    if invoice.status == "POSTED":
        return "Sent"
    return invoice.status


def get_bill_display_status(bill: Bill) -> str:
    """Map Bill internal status to visible business status."""
    if bill.status == "CANCELLED":
        return "Cancelled"
    if bill.status == "DRAFT":
        return "Draft"
    if bill.status == "PAID":
        return "Paid"
    if bill.status == "PARTIALLY_PAID":
        return "Partially Paid"
    if bill.status == "POSTED":
        return "Unpaid"
    return bill.status


def get_expense_display_status(expense: Expense) -> str:
    """Map Expense internal status to visible business status."""
    if expense.status == "CANCELLED":
        return "Cancelled"
    if expense.status == "DRAFT":
        return "Draft"
    if expense.status == "POSTED":
        return "Paid"
    return expense.status


def get_credit_note_display_status(cn: CreditNote) -> str:
    """Map CreditNote internal status to visible business status."""
    if cn.status == "CANCELLED":
        return "Cancelled"
    if cn.status == "DRAFT":
        return "Draft"
    if cn.status == "POSTED":
        return "Open"
    if cn.status == "ISSUED":
        return "Adjusted"
    return cn.status


def get_debit_note_display_status(dn: DebitNote) -> str:
    """Map DebitNote internal status to visible business status."""
    if dn.status == "CANCELLED":
        return "Cancelled"
    if dn.status == "DRAFT":
        return "Draft"
    if dn.status == "POSTED":
        return "Open"
    if dn.status == "ISSUED":
        return "Adjusted"
    return dn.status


# --- Helper to resolve all standard tax/round-off accounts ---------------

def _resolve_tax_accounts(resolver: AccountResolver, mode: str = "output"):
    """Returns dict of account IDs for CGST, SGST, IGST, UTGST, Cess, RoundOff.
    mode: 'output' for sales tax accounts, 'input' for purchase tax accounts.
    """
    suffix = "_output" if mode == "output" else "_input"
    return {
        "cgst": resolver.resolve(f"cgst{suffix}"),
        "sgst": resolver.resolve(f"sgst{suffix}"),
        "igst": resolver.resolve(f"igst{suffix}"),
        "utgst": resolver.resolve(f"utgst{suffix}"),
        "cess": resolver.resolve(f"cess{suffix}"),
        "round_off": resolver.resolve("round_off"),
    }


# --- Auto-Post Invoice ----------------------------------------------------

def auto_post_invoice(db: Session, tenant_id: uuid.UUID, invoice: Invoice) -> JournalEntry:
    """Auto-post an invoice on creation. Creates journal entry and sets status to POSTED."""
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_invoice_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        invoice_date=invoice.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
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
        round_off_amount=invoice.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Stock ledger: decrement stock for each product line
    for line in invoice.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if product:
                product.current_stock = (product.current_stock or Decimal("0")) - line.quantity
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    document_type="INVOICE",
                    document_id=invoice.id,
                    quantity=-line.quantity,
                    balance_after=product.current_stock,
                    notes=f"Invoice {invoice.invoice_number}",
                ))

    invoice.status = "POSTED"
    invoice.amount_paid = Decimal("0")
    db.flush()
    return invoice


# --- Auto-Post Bill ------------------------------------------------------

def auto_post_bill(db: Session, tenant_id: uuid.UUID, bill: Bill) -> JournalEntry:
    """Auto-post a bill on creation. Creates journal entry and sets status to POSTED."""
    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    tax = _resolve_tax_accounts(resolver, "input")

    draft = LedgerPostingEngine.create_bill_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        bill_date=bill.issue_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=bill.subtotal,
        discount_total=bill.discount_total,
        cgst_account_id=tax["cgst"],
        cgst_amount=bill.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=bill.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=bill.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=bill.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=bill.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=bill.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Stock ledger: increment stock for each product line
    for line in bill.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if product:
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    document_type="BILL",
                    document_id=bill.id,
                    quantity=line.quantity,
                    balance_after=product.current_stock,
                    notes=f"Bill {bill.bill_number}",
                ))

    bill.status = "POSTED"
    bill.amount_paid = Decimal("0")
    db.flush()
    return bill


# --- Auto-Post Expense ---------------------------------------------------

def auto_post_expense(db: Session, tenant_id: uuid.UUID, expense: Expense) -> JournalEntry:
    """Auto-post an expense on creation. Creates journal entry and sets status to POSTED."""
    from src.infrastructure.database.models import ExpenseCategory

    # Category relationship may not be loaded after flush; query explicitly
    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
        ExpenseCategory.tenant_id == tenant_id,
    ).first()
    expense_account_id = category.linked_account_id if category else None
    if not expense_account_id:
        resolver = AccountResolver(db, tenant_id)
        expense_account_id = resolver.resolve("expense.misc")

    resolver = AccountResolver(db, tenant_id)
    cash_account_id = resolver.resolve("assets.cash")
    tax = _resolve_tax_accounts(resolver, "input")

    draft = LedgerPostingEngine.create_expense_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        expense_date=expense.expense_date,
        expense_account_id=expense_account_id,
        cash_account_id=cash_account_id,
        amount=expense.amount,
        cgst_account_id=tax["cgst"],
        cgst_amount=expense.cgst_amount or Decimal("0"),
        sgst_account_id=tax["sgst"],
        sgst_amount=expense.sgst_amount or Decimal("0"),
        igst_account_id=tax["igst"],
        igst_amount=expense.igst_amount or Decimal("0"),
        utgst_account_id=tax["utgst"],
        utgst_amount=expense.utgst_amount or Decimal("0"),
        cess_account_id=tax["cess"],
        cess_amount=expense.cess_amount or Decimal("0"),
        round_off_account_id=tax["round_off"],
        round_off_amount=expense.round_off or Decimal("0"),
    )
    commit_ledger_draft(db, tenant_id, draft)

    expense.status = "POSTED"
    db.flush()
    return expense


# --- Auto-Post Credit Note -----------------------------------------------

def auto_post_credit_note(db: Session, tenant_id: uuid.UUID, cn: CreditNote) -> JournalEntry:
    """Auto-post a credit note on creation."""
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{cn.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_credit_note_posting(
        tenant_id=tenant_id,
        credit_note_id=cn.id,
        credit_note_number=cn.credit_note_number,
        issue_date=cn.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=cn.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=cn.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=cn.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=cn.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=cn.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=cn.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=cn.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    cn.status = "POSTED"
    db.flush()
    return cn


# --- Auto-Post Debit Note ------------------------------------------------

def auto_post_debit_note(db: Session, tenant_id: uuid.UUID, dn: DebitNote) -> JournalEntry:
    """Auto-post a debit note on creation."""
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{dn.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_debit_note_posting(
        tenant_id=tenant_id,
        debit_note_id=dn.id,
        debit_note_number=dn.debit_note_number,
        issue_date=dn.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=dn.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=dn.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=dn.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=dn.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=dn.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=dn.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=dn.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    dn.status = "POSTED"
    db.flush()
    return dn


# --- Cancel Invoice ------------------------------------------------------

def cancel_invoice(db: Session, tenant_id: uuid.UUID, invoice: Invoice, user_id: uuid.UUID) -> None:
    """Cancel a posted invoice. Creates reversing journal entries and sets CANCELLED status."""
    if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
        raise ValueError(f"Cannot cancel invoice in status {invoice.status}")

    from src.infrastructure.database.models import PaymentAllocation
    allocations = db.query(PaymentAllocation).filter(
        PaymentAllocation.invoice_id == invoice.id,
    ).first()
    if allocations:
        raise ValueError("Cannot cancel invoice with existing payments. Reverse payments first.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_invoice_reversal_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
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
        round_off_amount=invoice.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    invoice.status = "CANCELLED"
    invoice.amount_paid = Decimal("0")
    invoice.cancelled_at = datetime.now(timezone.utc)
    invoice.cancelled_by = user_id
    db.flush()


# --- Cancel Bill ---------------------------------------------------------

def cancel_bill(db: Session, tenant_id: uuid.UUID, bill: Bill, user_id: uuid.UUID) -> None:
    """Cancel a posted bill with reversing journal entries."""
    if bill.status not in ("POSTED", "PARTIALLY_PAID"):
        raise ValueError(f"Cannot cancel bill in status {bill.status}")

    from src.infrastructure.database.models import BillPaymentAllocation
    allocations = db.query(BillPaymentAllocation).filter(
        BillPaymentAllocation.bill_id == bill.id,
    ).first()
    if allocations:
        raise ValueError("Cannot cancel bill with existing payments. Reverse payments first.")

    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    tax = _resolve_tax_accounts(resolver, "input")

    draft = LedgerPostingEngine.create_bill_reversal_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        cancel_date=date.today(),
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=bill.subtotal,
        discount_total=bill.discount_total,
        cgst_account_id=tax["cgst"],
        cgst_amount=bill.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=bill.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=bill.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=bill.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=bill.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=bill.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    bill.status = "CANCELLED"
    bill.amount_paid = Decimal("0")
    bill.cancelled_at = datetime.now(timezone.utc)
    bill.cancelled_by = user_id
    db.flush()


# --- Cancel Expense ------------------------------------------------------

def cancel_expense(db: Session, tenant_id: uuid.UUID, expense: Expense, user_id: uuid.UUID) -> None:
    """Cancel a posted expense with reversing journal entries."""
    if expense.status != "POSTED":
        raise ValueError(f"Cannot cancel expense in status {expense.status}")

    resolver = AccountResolver(db, tenant_id)
    expense_account_id = expense.category.linked_account_id if expense.category else resolver.resolve("expense.misc")
    cash_account_id = resolver.resolve("assets.cash")
    tax = _resolve_tax_accounts(resolver, "input")

    draft = LedgerPostingEngine.create_expense_reversal_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        cancel_date=date.today(),
        expense_account_id=expense_account_id,
        cash_account_id=cash_account_id,
        amount=expense.amount,
        cgst_account_id=tax["cgst"],
        cgst_amount=expense.cgst_amount or Decimal("0"),
        sgst_account_id=tax["sgst"],
        sgst_amount=expense.sgst_amount or Decimal("0"),
        igst_account_id=tax["igst"],
        igst_amount=expense.igst_amount or Decimal("0"),
        utgst_account_id=tax["utgst"],
        utgst_amount=expense.utgst_amount or Decimal("0"),
        cess_account_id=tax["cess"],
        cess_amount=expense.cess_amount or Decimal("0"),
        round_off_account_id=tax["round_off"],
        round_off_amount=expense.round_off or Decimal("0"),
    )
    commit_ledger_draft(db, tenant_id, draft)

    expense.status = "CANCELLED"
    expense.cancelled_at = datetime.now(timezone.utc)
    expense.cancelled_by = user_id
    db.flush()


# --- Cancel Credit Note --------------------------------------------------

def cancel_credit_note(db: Session, tenant_id: uuid.UUID, cn: CreditNote, user_id: uuid.UUID) -> None:
    """Cancel a posted credit note with reversing journal entries."""
    if cn.status != "POSTED":
        raise ValueError(f"Cannot cancel credit note in status {cn.status}")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{cn.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_credit_note_reversal_posting(
        tenant_id=tenant_id,
        credit_note_id=cn.id,
        credit_note_number=cn.credit_note_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=cn.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=cn.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=cn.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=cn.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=cn.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=cn.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=cn.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    cn.status = "CANCELLED"
    cn.cancelled_at = datetime.now(timezone.utc)
    cn.cancelled_by = user_id
    db.flush()


# --- Cancel Debit Note ---------------------------------------------------

def cancel_debit_note(db: Session, tenant_id: uuid.UUID, dn: DebitNote, user_id: uuid.UUID) -> None:
    """Cancel a posted debit note with reversing journal entries."""
    if dn.status != "POSTED":
        raise ValueError(f"Cannot cancel debit note in status {dn.status}")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{dn.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_debit_note_reversal_posting(
        tenant_id=tenant_id,
        debit_note_id=dn.id,
        debit_note_number=dn.debit_note_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=dn.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=dn.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=dn.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=dn.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=dn.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=dn.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=dn.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    dn.status = "CANCELLED"
    dn.cancelled_at = datetime.now(timezone.utc)
    dn.cancelled_by = user_id
    db.flush()


# --- Record Invoice Payment ----------------------------------------------

def record_invoice_payment(
    db: Session,
    tenant_id: uuid.UUID,
    invoice: Invoice,
    payment_amount: Decimal,
    user_id: uuid.UUID,
) -> None:
    """Record a payment against an invoice. Updates amount_paid and status."""
    if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
        raise ValueError(f"Cannot record payment for invoice in status {invoice.status}")

    outstanding = invoice.total - invoice.amount_paid
    if payment_amount > outstanding:
        raise ValueError(f"Payment amount {payment_amount} exceeds outstanding {outstanding}")

    invoice.amount_paid = (invoice.amount_paid or Decimal("0")) + payment_amount
    if invoice.amount_paid >= invoice.total:
        invoice.status = "PAID"
    else:
        invoice.status = "PARTIALLY_PAID"
    db.flush()


# --- Record Bill Payment -------------------------------------------------

def record_bill_payment(
    db: Session,
    tenant_id: uuid.UUID,
    bill: Bill,
    payment_amount: Decimal,
    user_id: uuid.UUID,
) -> None:
    """Record a payment against a bill."""
    if bill.status not in ("POSTED", "PARTIALLY_PAID"):
        raise ValueError(f"Cannot record payment for bill in status {bill.status}")

    outstanding = bill.total - bill.amount_paid
    if payment_amount > outstanding:
        raise ValueError(f"Payment amount {payment_amount} exceeds outstanding {outstanding}")

    bill.amount_paid = (bill.amount_paid or Decimal("0")) + payment_amount
    if bill.amount_paid >= bill.total:
        bill.status = "PAID"
    else:
        bill.status = "PARTIALLY_PAID"
    db.flush()


# --- Auto-Post Sales Return ----------------------------------------------

def auto_post_sales_return(db: Session, tenant_id: uuid.UUID, sr: SalesReturn) -> JournalEntry:
    """Auto-post a sales return on creation. Stock comes IN."""
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{sr.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    draft = LedgerPostingEngine.create_sales_return_posting(
        tenant_id=tenant_id,
        return_id=sr.id,
        return_number=sr.return_number,
        return_date=sr.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=sr.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=sr.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=sr.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=sr.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=sr.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=sr.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=sr.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Stock ledger: increment stock for each product line (goods returned)
    for line in sr.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if product:
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    document_type="SALES_RETURN",
                    document_id=sr.id,
                    quantity=line.quantity,
                    balance_after=product.current_stock,
                    notes=f"Sales Return {sr.return_number}",
                ))

    sr.status = "POSTED"
    db.flush()
    return sr


# --- Auto-Post Purchase Return -----------------------------------------

def auto_post_purchase_return(db: Session, tenant_id: uuid.UUID, pr: PurchaseReturn) -> JournalEntry:
    """Auto-post a purchase return on creation. Stock goes OUT."""
    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{pr.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    tax = _resolve_tax_accounts(resolver, "input")

    draft = LedgerPostingEngine.create_purchase_return_posting(
        tenant_id=tenant_id,
        return_id=pr.id,
        return_number=pr.return_number,
        return_date=pr.issue_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=pr.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=pr.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=pr.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=pr.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=pr.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=pr.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=pr.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Stock ledger: decrement stock for each product line (goods returned to vendor)
    for line in pr.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if product:
                product.current_stock = (product.current_stock or Decimal("0")) - line.quantity
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    document_type="PURCHASE_RETURN",
                    document_id=pr.id,
                    quantity=-line.quantity,
                    balance_after=product.current_stock,
                    notes=f"Purchase Return {pr.return_number}",
                ))

    pr.status = "POSTED"
    db.flush()
    return pr


# --- Cancel Sales Return -------------------------------------------------

def cancel_sales_return(db: Session, tenant_id: uuid.UUID, sr: SalesReturn, user_id: uuid.UUID) -> None:
    """Cancel a posted sales return with reversing journal entries."""
    if sr.status != "POSTED":
        raise ValueError(f"Cannot cancel sales return in status {sr.status}")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{sr.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    # Reversal: opposite of sales return posting
    draft = LedgerPostingEngine.create_sales_return_posting(
        tenant_id=tenant_id,
        return_id=sr.id,
        return_number=sr.return_number,
        return_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=sr.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=sr.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=sr.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=sr.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=sr.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=sr.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=sr.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    sr.status = "CANCELLED"
    sr.cancelled_at = datetime.now(timezone.utc)
    sr.cancelled_by = user_id
    db.flush()


# --- Cancel Purchase Return ----------------------------------------------

def cancel_purchase_return(db: Session, tenant_id: uuid.UUID, pr: PurchaseReturn, user_id: uuid.UUID) -> None:
    """Cancel a posted purchase return with reversing journal entries."""
    if pr.status != "POSTED":
        raise ValueError(f"Cannot cancel purchase return in status {pr.status}")

    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{pr.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    tax = _resolve_tax_accounts(resolver, "input")

    draft = LedgerPostingEngine.create_purchase_return_posting(
        tenant_id=tenant_id,
        return_id=pr.id,
        return_number=pr.return_number,
        return_date=date.today(),
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=pr.subtotal,
        cgst_account_id=tax["cgst"],
        cgst_amount=pr.cgst_amount,
        sgst_account_id=tax["sgst"],
        sgst_amount=pr.sgst_amount,
        igst_account_id=tax["igst"],
        igst_amount=pr.igst_amount,
        utgst_account_id=tax["utgst"],
        utgst_amount=pr.utgst_amount,
        cess_account_id=tax["cess"],
        cess_amount=pr.cess_amount,
        round_off_account_id=tax["round_off"],
        round_off_amount=pr.round_off,
    )
    commit_ledger_draft(db, tenant_id, draft)

    pr.status = "CANCELLED"
    pr.cancelled_at = datetime.now(timezone.utc)
    pr.cancelled_by = user_id
    db.flush()
