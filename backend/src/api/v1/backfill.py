"""
Backfill ledger postings for imported documents.

Repair tool for tenants whose legacy import (Vyapar/Tally) predates
state-preserving posting: it finds every invoice, bill, customer payment and
vendor payment that is missing its journal entry and creates it, using the
exact same posting logic as the normal API paths, while leaving document
status, amounts paid, allocations and stock untouched.

Idempotent by construction (``_check_no_existing_posting``), single
transaction, and a failing document is rolled back individually and reported
instead of blocking the rest of the batch.
"""
from __future__ import annotations

import uuid
from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.database import get_db_session
from src.core.posting_context import set_session_posting_channel
from src.domains.accounting.backfill_posting import (
    post_bill_if_missing,
    post_bill_payment_if_missing,
    post_invoice_if_missing,
    post_payment_if_missing,
)
from src.infrastructure.database.models import (
    Bill,
    BillPayment,
    Invoice,
    Payment,
    User,
)

router = APIRouter()


@router.post("/import/backfill-postings")
def backfill_postings(
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("data:import")),
):
    """Create the missing ledger postings for imported invoices, bills and payments."""
    set_session_posting_channel(db, "IMPORT")

    posted_statuses = ("POSTED", "PARTIALLY_PAID", "PAID")
    invoices = db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at.is_(None),
        Invoice.status.in_(posted_statuses),
    ).all()
    bills = db.query(Bill).filter(
        Bill.tenant_id == tenant_id,
        Bill.deleted_at.is_(None),
        Bill.status.in_(posted_statuses),
    ).all()
    payments = db.query(Payment).filter(
        Payment.tenant_id == tenant_id,
        Payment.deleted_at.is_(None),
        Payment.status == "ACTIVE",
    ).all()
    bill_payments = db.query(BillPayment).filter(
        BillPayment.tenant_id == tenant_id,
        BillPayment.deleted_at.is_(None),
        BillPayment.status == "ACTIVE",
    ).all()

    counts = {
        "invoices_posted": 0,
        "bills_posted": 0,
        "customer_payments_posted": 0,
        "vendor_payments_posted": 0,
        "invoices_skipped": 0,
        "bills_skipped": 0,
        "customer_payments_skipped": 0,
        "vendor_payments_skipped": 0,
    }
    errors: List[str] = []

    def _attempt(label: str, doc_id: uuid.UUID, fn) -> None:
        try:
            # Savepoint: a failing document rolls back only itself, never the
            # postings already created in this batch.
            with db.begin_nested():
                fn()
            counts[label] += 1
        except ValueError:
            # Already posted (or otherwise intentionally skipped) — idempotent.
            counts[label.replace("_posted", "_skipped")] += 1
        except Exception as exc:  # noqa: BLE001 — per-document repair must not block the batch
            errors.append(f"{label}: {doc_id} — {exc}")

    for inv in invoices:
        _attempt("invoices_posted", inv.id, lambda i=inv: post_invoice_if_missing(db, tenant_id, i))
    for bill in bills:
        _attempt("bills_posted", bill.id, lambda b=bill: post_bill_if_missing(db, tenant_id, b))
    for pay in payments:
        _attempt("customer_payments_posted", pay.id, lambda p=pay: post_payment_if_missing(db, tenant_id, p))
    for bp in bill_payments:
        _attempt("vendor_payments_posted", bp.id, lambda b=bp: post_bill_payment_if_missing(db, tenant_id, b))

    db.commit()
    return {**counts, "errors": errors}
