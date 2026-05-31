"""
Auto-posting service for financial documents.

When a document is created, this module:
1. Persists the document with POSTED status (or business status)
2. Creates the journal entry via LedgerPostingEngine
3. Commits to the ledger in real-time

When a document is cancelled:
1. Creates reversing journal entries
2. Sets CANCELLED status

This removes the manual DRAFT → POSTED step for all financial documents.
"""
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from sqlalchemy.orm import Session

from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Bill, BillLine, Expense, CreditNote, DebitNote,
    JournalEntry, Account, Contact, TenantMembership,
)
from src.domains.accounting.services import (
    LedgerPostingEngine, JournalEntryDraft, commit_ledger_draft, AccountResolver,
)
from src.common.audit_log import set_audit_context


# ─── Status Mapping ───────────────────────────────────────────

# Maps internal status + payment state → user-facing business status
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


# ─── Auto-Post Invoice ───────────────────────────────────────

def auto_post_invoice(db: Session, tenant_id: uuid.UUID, invoice: Invoice) -> JournalEntry:
    """
    Auto-post an invoice on creation.
    Creates journal entry and sets status to POSTED.
    """
    draft = LedgerPostingEngine.create_invoice_posting(
        db=db,
        tenant_id=tenant_id,
        invoice=invoice,
    )
    commit_ledger_draft(db, tenant_id, draft)

    invoice.status = "POSTED"
    invoice.amount_paid = Decimal("0")
    db.flush()
    return invoice


# ─── Auto-Post Bill ──────────────────────────────────────────

def auto_post_bill(db: Session, tenant_id: uuid.UUID, bill: Bill) -> JournalEntry:
    """
    Auto-post a bill on creation.
    Creates journal entry and sets status to POSTED (displayed as "Unpaid").
    """
    draft = LedgerPostingEngine.create_bill_posting(
        db=db,
        tenant_id=tenant_id,
        bill=bill,
    )
    commit_ledger_draft(db, tenant_id, draft)

    bill.status = "POSTED"
    bill.amount_paid = Decimal("0")
    db.flush()
    return bill


# ─── Auto-Post Expense ───────────────────────────────────────

def auto_post_expense(db: Session, tenant_id: uuid.UUID, expense: Expense) -> JournalEntry:
    """
    Auto-post an expense on creation.
    Creates journal entry and sets status to POSTED (displayed as "Paid").
    """
    draft = LedgerPostingEngine.create_expense_posting(
        db=db,
        tenant_id=tenant_id,
        expense=expense,
    )
    commit_ledger_draft(db, tenant_id, draft)

    expense.status = "POSTED"
    db.flush()
    return expense


# ─── Auto-Post Credit Note ───────────────────────────────────

def auto_post_credit_note(db: Session, tenant_id: uuid.UUID, cn: CreditNote) -> JournalEntry:
    """
    Auto-post a credit note on creation.
    Creates reversal journal entry and sets status to POSTED (displayed as "Open").
    """
    draft = LedgerPostingEngine.create_credit_note_posting(
        db=db,
        tenant_id=tenant_id,
        credit_note=cn,
    )
    commit_ledger_draft(db, tenant_id, draft)

    cn.status = "POSTED"
    db.flush()
    return cn


# ─── Auto-Post Debit Note ────────────────────────────────────

def auto_post_debit_note(db: Session, tenant_id: uuid.UUID, dn: DebitNote) -> JournalEntry:
    """
    Auto-post a debit note on creation.
    Creates journal entry and sets status to POSTED (displayed as "Open").
    """
    draft = LedgerPostingEngine.create_debit_note_posting(
        db=db,
        tenant_id=tenant_id,
        debit_note=dn,
    )
    commit_ledger_draft(db, tenant_id, draft)

    dn.status = "POSTED"
    db.flush()
    return dn


# ─── Cancel Invoice ──────────────────────────────────────────

def cancel_invoice(db: Session, tenant_id: uuid.UUID, invoice: Invoice, user_id: uuid.UUID) -> None:
    """
    Cancel a posted invoice.
    Creates reversing journal entries and sets CANCELLED status.
    """
    if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
        raise ValueError(f"Cannot cancel invoice in status {invoice.status}")

    from src.infrastructure.database.models import PaymentAllocation
    allocations = db.query(PaymentAllocation).filter(
        PaymentAllocation.invoice_id == invoice.id,
    ).first()
    if allocations:
        raise ValueError("Cannot cancel invoice with existing payments. Reverse payments first.")

    draft = LedgerPostingEngine.create_invoice_reversal_posting(
        db=db,
        tenant_id=tenant_id,
        invoice=invoice,
    )
    commit_ledger_draft(db, tenant_id, draft)

    invoice.status = "CANCELLED"
    invoice.amount_paid = Decimal("0")
    invoice.cancelled_at = datetime.now(timezone.utc)
    invoice.cancelled_by = user_id
    db.flush()


# ─── Cancel Bill ─────────────────────────────────────────────

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

    draft = LedgerPostingEngine.create_bill_reversal_posting(
        db=db,
        tenant_id=tenant_id,
        bill=bill,
    )
    commit_ledger_draft(db, tenant_id, draft)

    bill.status = "CANCELLED"
    bill.amount_paid = Decimal("0")
    bill.cancelled_at = datetime.now(timezone.utc)
    bill.cancelled_by = user_id
    db.flush()


# ─── Cancel Expense ──────────────────────────────────────────

def cancel_expense(db: Session, tenant_id: uuid.UUID, expense: Expense, user_id: uuid.UUID) -> None:
    """Cancel a posted expense with reversing journal entries."""
    if expense.status != "POSTED":
        raise ValueError(f"Cannot cancel expense in status {expense.status}")

    draft = LedgerPostingEngine.create_expense_reversal_posting(
        db=db,
        tenant_id=tenant_id,
        expense=expense,
    )
    commit_ledger_draft(db, tenant_id, draft)

    expense.status = "CANCELLED"
    expense.cancelled_at = datetime.now(timezone.utc)
    expense.cancelled_by = user_id
    db.flush()


# ─── Cancel Credit Note ──────────────────────────────────────

def cancel_credit_note(db: Session, tenant_id: uuid.UUID, cn: CreditNote, user_id: uuid.UUID) -> None:
    """Cancel a posted credit note with reversing journal entries."""
    if cn.status != "POSTED":
        raise ValueError(f"Cannot cancel credit note in status {cn.status}")

    draft = LedgerPostingEngine.create_credit_note_reversal_posting(
        db=db,
        tenant_id=tenant_id,
        credit_note=cn,
    )
    commit_ledger_draft(db, tenant_id, draft)

    cn.status = "CANCELLED"
    cn.cancelled_at = datetime.now(timezone.utc)
    cn.cancelled_by = user_id
    db.flush()


# ─── Cancel Debit Note ───────────────────────────────────────

def cancel_debit_note(db: Session, tenant_id: uuid.UUID, dn: DebitNote, user_id: uuid.UUID) -> None:
    """Cancel a posted debit note with reversing journal entries."""
    if dn.status != "POSTED":
        raise ValueError(f"Cannot cancel debit note in status {dn.status}")

    draft = LedgerPostingEngine.create_debit_note_reversal_posting(
        db=db,
        tenant_id=tenant_id,
        debit_note=dn,
    )
    commit_ledger_draft(db, tenant_id, draft)

    dn.status = "CANCELLED"
    dn.cancelled_at = datetime.now(timezone.utc)
    dn.cancelled_by = user_id
    db.flush()


# ─── Record Invoice Payment ──────────────────────────────────

def record_invoice_payment(
    db: Session,
    tenant_id: uuid.UUID,
    invoice: Invoice,
    payment_amount: Decimal,
    user_id: uuid.UUID,
) -> None:
    """
    Record a payment against an invoice.
    Updates amount_paid, status, and creates journal entry.
    """
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


# ─── Record Bill Payment ─────────────────────────────────────

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
