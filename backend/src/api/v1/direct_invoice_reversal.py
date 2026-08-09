"""Correct invoice reversal adapter for the direct public contract.

The legacy public `/cancel` handler predates shipping/RCM posting arguments and
constructs its reversal inline.  Direct Edit/Delete must reverse the exact
accounting fact that was posted, including shipping and reverse-charge rules,
so this adapter delegates to the canonical auto-post reversal service instead.
"""

import uuid

from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.database import get_db_session
from src.domains.accounting.auto_post import cancel_invoice as cancel_invoice_posting
from src.domains.taxation.filing_lock import ensure_outward_period_mutable, GSTPeriodFiledError
from src.infrastructure.database.models import Invoice, PaymentAllocation, User


def cancel_invoice_for_direct_correction(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
    current_user: User = Depends(get_current_user),
):
    """Reverse a posted invoice without exposing a public Cancel workflow.

    The caller may pass the normal Session or the direct-contract
    DeferredCommitSession.  In the latter case the legacy `commit` boundary is
    deliberately deferred so reversal + replacement remain atomic.
    """
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open

    validate_period_open(db, tenant_id, invoice.issue_date)
    try:
        ensure_outward_period_mutable(db, tenant_id, invoice.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    if invoice.status == "SENT":
        # SENT is a presentation/business state for a financially posted invoice.
        invoice.status = "POSTED"
    if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
        raise HTTPException(
            status_code=409,
            detail="This invoice is not in a reversible accounting state.",
        )

    if db.query(PaymentAllocation.id).filter(
        PaymentAllocation.invoice_id == invoice.id,
        PaymentAllocation.tenant_id == tenant_id,
    ).first():
        raise HTTPException(
            status_code=409,
            detail="Reverse applied receipt(s) before correcting this invoice.",
        )

    try:
        # Canonical service includes shipping_charges, RCM, all GST components,
        # round-off, stock reversal and immutable reversal linkage.
        cancel_invoice_posting(db, tenant_id, invoice, current_user.id)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    db.commit()
    db.refresh(invoice)
    return invoice


def install_direct_invoice_reversal() -> None:
    # The direct route handlers look up invoice_api.cancel_invoice at execution
    # time, so replacing this internal callable does not re-expose /cancel and
    # keeps the public router unchanged.
    from src.api.v1 import invoices as invoice_api

    invoice_api.cancel_invoice = cancel_invoice_for_direct_correction
