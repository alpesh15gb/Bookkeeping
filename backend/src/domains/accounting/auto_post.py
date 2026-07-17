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
from src.domains.inventory.services import (
    resolve_default_warehouse_id,
    resolve_reversal_warehouse_id,
    get_warehouse_stock,
    get_stock_balance_after,
)


def _check_no_existing_posting(db: Session, tenant_id: uuid.UUID, source_type: str, source_id: uuid.UUID) -> None:
    """Guard: prevent duplicate journal entries for the same document.
    Uses SELECT FOR UPDATE to prevent race condition between concurrent requests."""
    from src.infrastructure.database.models import JournalEntry
    existing = db.query(JournalEntry.id).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == source_type,
        JournalEntry.source_id == source_id,
    ).with_for_update().first()
    if existing:
        raise ValueError(f"Document {source_type}:{source_id} already has a journal entry. Duplicate posting blocked.")


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

def auto_post_invoice(
    db: Session,
    tenant_id: uuid.UUID,
    invoice: Invoice,
    allow_negative_stock: bool = False,
    move_stock: bool = True,
) -> JournalEntry:
    """Auto-post an invoice on creation. Creates journal entry and sets status to POSTED."""
    _check_no_existing_posting(db, tenant_id, "INVOICE", invoice.id)
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
        round_off_amount=invoice.round_off,
        is_rcm=invoice.is_rcm,
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Stock ledger: decrement stock for each product line
    for line in invoice.lines if move_stock else ():
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                available = product.current_stock or Decimal("0")
                warehouse_id = resolve_default_warehouse_id(db, tenant_id)
                location_available = get_warehouse_stock(
                    db, tenant_id, warehouse_id, line.product_id
                )
                effective_available = location_available if location_available is not None else available
                if not allow_negative_stock and effective_available < line.quantity:
                    raise ValueError(f"Insufficient stock for {product.name} in the default warehouse. Available: {effective_available}, Required: {line.quantity}")
                product.current_stock = available - line.quantity
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    -line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="INVOICE",
                    reference_id=invoice.id,
                    quantity=-line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

    invoice.status = "POSTED"
    invoice.amount_paid = Decimal("0")
    db.flush()
    return invoice


# --- Auto-Post Bill ------------------------------------------------------

def auto_post_bill(db: Session, tenant_id: uuid.UUID, bill: Bill) -> JournalEntry:
    """Auto-post a bill on creation. Creates journal entry and sets status to POSTED."""
    _check_no_existing_posting(db, tenant_id, "BILL", bill.id)

    # Duplicate bill number guard per vendor
    existing = db.query(Bill).filter(
        Bill.tenant_id == tenant_id,
        Bill.contact_id == bill.contact_id,
        Bill.bill_number == bill.bill_number,
        Bill.deleted_at == None,
    ).first()
    if existing and existing.id != bill.id:
        raise ValueError(f"Duplicate bill number {bill.bill_number} for this vendor.")

    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    tax = _resolve_tax_accounts(resolver, "input")
    tds_account_id = resolver.resolve("liability.tds") if bill.tds_amount and bill.tds_amount > 0 else None
    tax_total = (
        bill.cgst_amount + bill.sgst_amount + bill.igst_amount
        + bill.utgst_amount + bill.cess_amount
    )
    posting_subtotal = bill.subtotal if bill.itc_eligible else bill.subtotal + tax_total
    posting_cgst = bill.cgst_amount if bill.itc_eligible else Decimal("0")
    posting_sgst = bill.sgst_amount if bill.itc_eligible else Decimal("0")
    posting_igst = bill.igst_amount if bill.itc_eligible else Decimal("0")
    posting_utgst = bill.utgst_amount if bill.itc_eligible else Decimal("0")
    posting_cess = bill.cess_amount if bill.itc_eligible else Decimal("0")

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
        cgst_amount=posting_cgst,
        sgst_account_id=tax["sgst"],
        sgst_amount=posting_sgst,
        igst_account_id=tax["igst"],
        igst_amount=posting_igst,
        utgst_account_id=tax["utgst"],
        utgst_amount=posting_utgst,
        cess_account_id=tax["cess"],
        cess_amount=posting_cess,
        round_off_account_id=tax["round_off"],
        round_off_amount=bill.round_off,
        tds_account_id=tds_account_id,
        tds_amount=bill.tds_amount or Decimal("0"),
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Stock ledger: increment stock for each product line
    for line in bill.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                warehouse_id = resolve_default_warehouse_id(db, tenant_id)
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="BILL",
                    reference_id=bill.id,
                    quantity=line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

    bill.status = "POSTED"
    bill.amount_paid = Decimal("0")
    db.flush()
    return bill


# --- Auto-Post Expense ---------------------------------------------------
# NOTE: Expenses are NOT auto-posted on creation. They require a manual /post call.
# This is a deliberate design: expenses often need review before posting (e.g., receipt
# attachment, approval workflows). The /post endpoint in expenses.py handles posting
# with the correct bank_account_id from the expense record.
#
# auto_post_expense below is used ONLY by batch import tools (Vyapar, Tally) that
# create already-verified expenses. It uses the default cash account since imported
# expenses may not have a bank_account_id.

def auto_post_expense(db: Session, tenant_id: uuid.UUID, expense: Expense) -> JournalEntry:
    """Auto-post an expense on creation. Creates journal entry and sets status to POSTED."""
    _check_no_existing_posting(db, tenant_id, "EXPENSE", expense.id)
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
    cash_account_id = expense.bank_account_id if expense.bank_account_id else resolver.resolve("assets.cash")
    tax = _resolve_tax_accounts(resolver, "input")
    from src.domains.taxation.services import GSTEngine
    claim_itc = GSTEngine.can_claim_itc(db, tenant_id, True)
    tax_total = (
        (expense.cgst_amount or Decimal("0"))
        + (expense.sgst_amount or Decimal("0"))
        + (expense.igst_amount or Decimal("0"))
        + (expense.utgst_amount or Decimal("0"))
        + (expense.cess_amount or Decimal("0"))
    )
    posting_amount = expense.amount if claim_itc else expense.amount + tax_total

    draft = LedgerPostingEngine.create_expense_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        expense_date=expense.expense_date,
        expense_account_id=expense_account_id,
        cash_account_id=cash_account_id,
        amount=posting_amount,
        cgst_account_id=tax["cgst"],
        cgst_amount=(expense.cgst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        sgst_account_id=tax["sgst"],
        sgst_amount=(expense.sgst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        igst_account_id=tax["igst"],
        igst_amount=(expense.igst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        utgst_account_id=tax["utgst"],
        utgst_amount=(expense.utgst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        cess_account_id=tax["cess"],
        cess_amount=(expense.cess_amount or Decimal("0")) if claim_itc else Decimal("0"),
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
    _check_no_existing_posting(db, tenant_id, "CREDIT_NOTE", cn.id)
    contact_id = cn.invoice.contact_id if cn.invoice else None
    if not contact_id:
        raise ValueError("Credit Note must be linked to an invoice with a contact.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
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
    _check_no_existing_posting(db, tenant_id, "DEBIT_NOTE", dn.id)
    contact_id = dn.invoice.contact_id if dn.invoice else None
    if not contact_id:
        raise ValueError("Debit Note must be linked to an invoice with a contact.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
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

    from src.infrastructure.database.models import PaymentAllocation, JournalEntry, JournalLine
    allocations = db.query(PaymentAllocation).filter(
        PaymentAllocation.invoice_id == invoice.id,
    ).first()
    if allocations:
        raise ValueError("Cannot cancel invoice with existing payments. Reverse payments first.")

    # Secondary guard: check for any PAYMENT journal entries linked to this contact
    # after the invoice date (catches direct payments without allocation records)
    payment_entries = db.query(JournalEntry).join(
        JournalLine, JournalLine.entry_id == JournalEntry.id
    ).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type.in_(["PAYMENT"]),
        JournalEntry.entry_date >= invoice.issue_date,
    ).first()
    if payment_entries:
        # Verify the payment is for the same contact by checking the customer account
        customer_account_id = db.query(Account.id).filter(
            Account.tenant_id == tenant_id,
            Account.name.ilike(f"%{invoice.contact.name}%"),
            Account.account_type == "ASSET",
        ).first()
        if customer_account_id:
            linked_payment = db.query(JournalLine).filter(
                JournalLine.entry_id == payment_entries.id,
                JournalLine.account_id == customer_account_id[0],
            ).first()
            if linked_payment:
                raise ValueError("Cannot cancel: active payment journal entries exist for this customer. Reverse payments first.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    tax = _resolve_tax_accounts(resolver, "output")

    # Use invoice date for cancellation, not today — ensures reversal falls in same period
    cancel_date = invoice.issue_date

    draft = LedgerPostingEngine.create_invoice_reversal_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        cancel_date=cancel_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
        shipping_charges=invoice.shipping_charges or Decimal("0"),
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
        is_rcm=invoice.is_rcm,
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Reverse stock ledger: increment stock for each product line (restoring stock)
    for line in invoice.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                warehouse_id = resolve_reversal_warehouse_id(
                    db, tenant_id, "INVOICE", invoice.id, line.product_id
                )
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="INVOICE_REVERSAL",
                    reference_id=invoice.id,
                    quantity=line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

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
    tds_account_id = resolver.resolve("liability.tds") if bill.tds_amount and bill.tds_amount > 0 else None
    tax_total = (
        bill.cgst_amount + bill.sgst_amount + bill.igst_amount
        + bill.utgst_amount + bill.cess_amount
    )
    posting_subtotal = bill.subtotal if bill.itc_eligible else bill.subtotal + tax_total
    posting_cgst = bill.cgst_amount if bill.itc_eligible else Decimal("0")
    posting_sgst = bill.sgst_amount if bill.itc_eligible else Decimal("0")
    posting_igst = bill.igst_amount if bill.itc_eligible else Decimal("0")
    posting_utgst = bill.utgst_amount if bill.itc_eligible else Decimal("0")
    posting_cess = bill.cess_amount if bill.itc_eligible else Decimal("0")

    cancel_date = bill.issue_date

    draft = LedgerPostingEngine.create_bill_reversal_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        cancel_date=cancel_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=posting_subtotal,
        discount_total=bill.discount_total,
        shipping_charges=bill.shipping_charges or Decimal("0"),
        cgst_account_id=tax["cgst"],
        cgst_amount=posting_cgst,
        sgst_account_id=tax["sgst"],
        sgst_amount=posting_sgst,
        igst_account_id=tax["igst"],
        igst_amount=posting_igst,
        utgst_account_id=tax["utgst"],
        utgst_amount=posting_utgst,
        cess_account_id=tax["cess"],
        cess_amount=posting_cess,
        round_off_account_id=tax["round_off"],
        round_off_amount=bill.round_off,
        tds_account_id=tds_account_id,
        tds_amount=bill.tds_amount or Decimal("0"),
    )
    commit_ledger_draft(db, tenant_id, draft)

    # Reverse stock ledger: decrement stock for each product line (reversing the purchase)
    for line in bill.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                available = product.current_stock or Decimal("0")
                warehouse_id = resolve_reversal_warehouse_id(
                    db, tenant_id, "BILL", bill.id, line.product_id
                )
                location_available = get_warehouse_stock(
                    db, tenant_id, warehouse_id, line.product_id
                )
                effective_available = location_available if location_available is not None else available
                if effective_available < line.quantity:
                    raise ValueError(f"Insufficient stock for {product.name} in the receiving warehouse. Available: {effective_available}, Required: {line.quantity}")
                product.current_stock = available - line.quantity
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    -line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="BILL_REVERSAL",
                    reference_id=bill.id,
                    quantity=-line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

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
    from src.infrastructure.database.models import ExpenseCategory
    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
        ExpenseCategory.tenant_id == tenant_id,
    ).first()
    expense_account_id = category.linked_account_id if category else resolver.resolve("expense.misc")
    cash_account_id = expense.bank_account_id if expense.bank_account_id else resolver.resolve("assets.cash")
    tax = _resolve_tax_accounts(resolver, "input")
    from src.domains.taxation.services import GSTEngine
    claim_itc = GSTEngine.can_claim_itc(db, tenant_id, True)
    tax_total = (
        (expense.cgst_amount or Decimal("0"))
        + (expense.sgst_amount or Decimal("0"))
        + (expense.igst_amount or Decimal("0"))
        + (expense.utgst_amount or Decimal("0"))
        + (expense.cess_amount or Decimal("0"))
    )
    posting_amount = expense.amount if claim_itc else expense.amount + tax_total

    draft = LedgerPostingEngine.create_expense_reversal_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        cancel_date=date.today(),
        expense_account_id=expense_account_id,
        cash_account_id=cash_account_id,
        amount=posting_amount,
        cgst_account_id=tax["cgst"],
        cgst_amount=(expense.cgst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        sgst_account_id=tax["sgst"],
        sgst_amount=(expense.sgst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        igst_account_id=tax["igst"],
        igst_amount=(expense.igst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        utgst_account_id=tax["utgst"],
        utgst_amount=(expense.utgst_amount or Decimal("0")) if claim_itc else Decimal("0"),
        cess_account_id=tax["cess"],
        cess_amount=(expense.cess_amount or Decimal("0")) if claim_itc else Decimal("0"),
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

    contact_id = cn.invoice.contact_id if cn.invoice else None
    if not contact_id:
        raise ValueError("Credit Note must be linked to an invoice for cancellation.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
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

    contact_id = dn.invoice.contact_id if dn.invoice else None
    if not contact_id:
        raise ValueError("Debit Note must be linked to an invoice for cancellation.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
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
    payment_amount = Decimal(str(payment_amount))
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
    payment_amount = Decimal(str(payment_amount))
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
    _check_no_existing_posting(db, tenant_id, "SALES_RETURN", sr.id)
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
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                warehouse_id = resolve_default_warehouse_id(db, tenant_id)
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="SALES_RETURN",
                    reference_id=sr.id,
                    quantity=line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

    sr.status = "POSTED"
    db.flush()
    return sr


# --- Auto-Post Purchase Return -----------------------------------------

def auto_post_purchase_return(db: Session, tenant_id: uuid.UUID, pr: PurchaseReturn) -> JournalEntry:
    """Auto-post a purchase return on creation. Stock goes OUT."""
    _check_no_existing_posting(db, tenant_id, "PURCHASE_RETURN", pr.id)
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
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                available = product.current_stock or Decimal("0")
                warehouse_id = resolve_default_warehouse_id(db, tenant_id)
                location_available = get_warehouse_stock(
                    db, tenant_id, warehouse_id, line.product_id
                )
                effective_available = location_available if location_available is not None else available
                if effective_available < line.quantity:
                    raise ValueError(f"Insufficient stock for {product.name} in the default warehouse. Available: {effective_available}, Required: {line.quantity}")
                product.current_stock = available - line.quantity
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    -line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="PURCHASE_RETURN",
                    reference_id=pr.id,
                    quantity=-line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
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

    draft = LedgerPostingEngine.create_sales_return_reversal_posting(
        tenant_id=tenant_id,
        return_id=sr.id,
        return_number=sr.return_number,
        cancel_date=date.today(),
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

    # Reverse stock: decrement stock (undoing the stock that came in from the sales return)
    for line in sr.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                available = product.current_stock or Decimal("0")
                warehouse_id = resolve_reversal_warehouse_id(
                    db, tenant_id, "SALES_RETURN", sr.id, line.product_id
                )
                location_available = get_warehouse_stock(
                    db, tenant_id, warehouse_id, line.product_id
                )
                effective_available = location_available if location_available is not None else available
                if effective_available < line.quantity:
                    raise ValueError(f"Cannot cancel sales return: insufficient stock for {product.name} in its warehouse. Available: {effective_available}, Required: {line.quantity}")
                product.current_stock = available - line.quantity
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    -line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="SALES_RETURN_REVERSAL",
                    reference_id=sr.id,
                    quantity=-line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

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

    draft = LedgerPostingEngine.create_purchase_return_reversal_posting(
        tenant_id=tenant_id,
        return_id=pr.id,
        return_number=pr.return_number,
        cancel_date=date.today(),
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

    # Reverse stock: increment stock (undoing the stock that was removed from the purchase return)
    for line in pr.lines:
        if line.product_id and line.quantity:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).with_for_update().first()
            if product and product.product_type == "GOODS":
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                warehouse_id = resolve_reversal_warehouse_id(
                    db, tenant_id, "PURCHASE_RETURN", pr.id, line.product_id
                )
                balance_after = get_stock_balance_after(
                    db, tenant_id, warehouse_id, line.product_id,
                    line.quantity, product.current_stock,
                )
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    warehouse_id=warehouse_id,
                    reference_type="PURCHASE_RETURN_REVERSAL",
                    reference_id=pr.id,
                    quantity=line.quantity,
                    balance_quantity=balance_after,
                    rate=line.rate,
                ))

    pr.status = "CANCELLED"
    pr.cancelled_at = datetime.now(timezone.utc)
    pr.cancelled_by = user_id
    db.flush()
