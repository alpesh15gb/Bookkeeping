import uuid
from datetime import date, datetime, timezone
from typing import Optional

from fastapi import Depends, HTTPException, Request, Response, status
from pydantic import Field
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.config import settings
from src.core.database import get_db_session
from src.core.rate_limiter import limiter
from src.infrastructure.database.models import (
    BillPayment,
    CreditNote,
    DebitNote,
    InventoryAdjustment,
    JournalEntry,
    Payment,
    PurchaseReturn,
    SalesReturn,
    User,
)
from src.schemas.accounting_schemas import (
    JournalEntryCreate,
    JournalEntryResponse,
    JournalReversalCreate,
)
from src.schemas.bill_schemas import (
    InventoryAdjustmentCreate,
    InventoryAdjustmentLineCreate,
    InventoryAdjustmentResponse,
    InventoryAdjustmentUpdate,
)
from src.schemas.document import (
    CreditNoteCreate,
    CreditNoteResponse,
    DebitNoteCreate,
    DebitNoteResponse,
    PurchaseReturnCreate,
    PurchaseReturnResponse,
    SalesReturnCreate,
    SalesReturnResponse,
)
from src.schemas.payment_schemas import (
    BillPaymentCreate,
    BillPaymentResponse,
    PaymentCancel,
    PaymentCreate,
    PaymentResponse,
)
from src.api.v1.direct_posting_contract import (
    DeferredCommitSession,
    _begin_replacement,
    _end_replacement,
    _remove_route,
    _set_replay_resource,
    _unwrap,
)
from src.api.v1 import accounting as accounting_api
from src.api.v1 import inventory_adjustments as inventory_api
from src.api.v1 import invoices as invoice_api
from src.api.v1 import payments as payment_api
from src.api.v1 import returns as return_api


def _soft_delete(obj) -> None:
    obj.deleted_at = datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Credit / debit notes
# ---------------------------------------------------------------------------

def direct_create_credit_note(
    payload: CreditNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create")),
):
    proxy = DeferredCommitSession(db)
    note = _unwrap(invoice_api.create_credit_note)(payload, proxy, tenant_id)
    note = _unwrap(invoice_api.finalize_credit_note)(note.id, proxy, tenant_id)
    db.commit()
    db.refresh(note)
    return note


def direct_update_credit_note(
    id: uuid.UUID,
    payload: CreditNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(CreditNote).filter(
        CreditNote.id == id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Credit Note not found.")

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, CreditNote, original)
    try:
        if original.status != "DRAFT":
            _unwrap(invoice_api.cancel_credit_note)(id, proxy, tenant_id, current_user)
        _soft_delete(original)
        replacement_payload = payload.model_copy(update={"credit_note_number": None})
        replacement = _unwrap(invoice_api.create_credit_note)(
            replacement_payload, proxy, tenant_id
        )
        replacement = _unwrap(invoice_api.finalize_credit_note)(
            replacement.id, proxy, tenant_id
        )
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_credit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(CreditNote).filter(
        CreditNote.id == id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Credit Note not found.")
    proxy = DeferredCommitSession(db)
    if original.status != "DRAFT":
        _unwrap(invoice_api.cancel_credit_note)(id, proxy, tenant_id, current_user)
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def direct_create_debit_note(
    payload: DebitNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("debit_note:create")),
):
    proxy = DeferredCommitSession(db)
    note = _unwrap(invoice_api.create_debit_note)(payload, proxy, tenant_id)
    note = _unwrap(invoice_api.finalize_debit_note)(note.id, proxy, tenant_id)
    db.commit()
    db.refresh(note)
    return note


def direct_update_debit_note(
    id: uuid.UUID,
    payload: DebitNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("debit_note:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(DebitNote).filter(
        DebitNote.id == id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Debit Note not found.")

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, DebitNote, original)
    try:
        if original.status != "DRAFT":
            _unwrap(invoice_api.cancel_debit_note)(id, proxy, tenant_id, current_user)
        _soft_delete(original)
        replacement_payload = payload.model_copy(update={"debit_note_number": None})
        replacement = _unwrap(invoice_api.create_debit_note)(
            replacement_payload, proxy, tenant_id
        )
        replacement = _unwrap(invoice_api.finalize_debit_note)(
            replacement.id, proxy, tenant_id
        )
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_debit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("debit_note:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(DebitNote).filter(
        DebitNote.id == id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Debit Note not found.")
    proxy = DeferredCommitSession(db)
    if original.status != "DRAFT":
        _unwrap(invoice_api.cancel_debit_note)(id, proxy, tenant_id, current_user)
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Inventory adjustments
# ---------------------------------------------------------------------------

class DirectInventoryAdjustmentCreate(InventoryAdjustmentCreate):
    adjustment_number: Optional[str] = Field(None, max_length=50)


def _inventory_lines(adjustment: InventoryAdjustment):
    return [
        InventoryAdjustmentLineCreate(
            product_id=line.product_id,
            quantity_change=line.quantity_change,
            unit_cost=line.unit_cost,
        )
        for line in adjustment.lines
    ]


def _inventory_create_payload(
    db: Session, tenant_id: uuid.UUID, payload: DirectInventoryAdjustmentCreate
) -> InventoryAdjustmentCreate:
    from src.domains.company.services import NumberingSeriesService

    values = payload.model_dump()
    values["adjustment_number"] = values.get("adjustment_number") or NumberingSeriesService.generate_next_number(
        db, tenant_id, "INVENTORY_ADJUSTMENT"
    )
    return InventoryAdjustmentCreate(**values)


def _link_inventory_reversal(
    db: Session,
    tenant_id: uuid.UUID,
    adjustment_id: uuid.UUID,
    user_id: uuid.UUID,
):
    original = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == "INVENTORY_ADJUSTMENT",
        JournalEntry.source_id == adjustment_id,
    ).first()
    reversal = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == "INVENTORY_ADJUSTMENT_REVERSAL",
        JournalEntry.source_id == adjustment_id,
    ).order_by(JournalEntry.created_at.desc()).first()
    if original and reversal:
        original.reversed_by = user_id
        original.reversed_at = datetime.now(timezone.utc)
        original.reversal_transaction_id = reversal.id
        reversal.reverses_transaction_id = original.id
        db.flush()
    return original


def direct_create_inventory_adjustment(
    payload: DirectInventoryAdjustmentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust")),
):
    proxy = DeferredCommitSession(db)
    adjustment = _unwrap(inventory_api.create_inventory_adjustment)(
        _inventory_create_payload(db, tenant_id, payload), proxy, tenant_id
    )
    adjustment = _unwrap(inventory_api.confirm_inventory_adjustment)(
        adjustment.id, proxy, tenant_id
    )
    _set_replay_resource(db, adjustment)
    db.commit()
    db.refresh(adjustment)
    return adjustment


def direct_update_inventory_adjustment(
    id: uuid.UUID,
    payload: InventoryAdjustmentUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Inventory Adjustment not found.")

    from src.domains.company.services import NumberingSeriesService

    replacement_number = payload.adjustment_number
    if not replacement_number or replacement_number == original.adjustment_number:
        replacement_number = NumberingSeriesService.generate_next_number(
            db, tenant_id, "INVENTORY_ADJUSTMENT"
        )
    replacement_payload = InventoryAdjustmentCreate(
        adjustment_number=replacement_number,
        adjustment_date=payload.adjustment_date or original.adjustment_date,
        reason=payload.reason if payload.reason is not None else original.reason,
        line_items=payload.line_items or _inventory_lines(original),
    )

    proxy = DeferredCommitSession(db)
    original_je = None
    _begin_replacement(db, InventoryAdjustment, original)
    try:
        if original.status == "CONFIRMED":
            _unwrap(inventory_api.cancel_inventory_adjustment)(id, proxy, tenant_id)
            original_je = _link_inventory_reversal(db, tenant_id, id, current_user.id)
        _soft_delete(original)

        replacement = _unwrap(inventory_api.create_inventory_adjustment)(
            replacement_payload, proxy, tenant_id
        )
        replacement = _unwrap(inventory_api.confirm_inventory_adjustment)(
            replacement.id, proxy, tenant_id
        )
        replacement_je = db.query(JournalEntry).filter(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.source_type == "INVENTORY_ADJUSTMENT",
            JournalEntry.source_id == replacement.id,
        ).first()
        if original_je and replacement_je:
            original_je.replacement_transaction_id = replacement_je.id
            replacement_je.original_transaction_id = original_je.id
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_inventory_adjustment(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(InventoryAdjustment).filter(
        InventoryAdjustment.id == id,
        InventoryAdjustment.tenant_id == tenant_id,
        InventoryAdjustment.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Inventory Adjustment not found.")
    proxy = DeferredCommitSession(db)
    if original.status == "CONFIRMED":
        _unwrap(inventory_api.cancel_inventory_adjustment)(id, proxy, tenant_id)
        _link_inventory_reversal(db, tenant_id, id, current_user.id)
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Payments: one central API; edits reverse + recreate, deletes reverse + hide.
# ---------------------------------------------------------------------------

@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_update_receipt(
    request: Request,
    id: uuid.UUID,
    payload: PaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:update")),
):
    original = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id,
        Payment.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Payment receipt not found.")

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, Payment, original)
    try:
        _unwrap(payment_api.cancel_payment_receipt)(
            id,
            PaymentCancel(reason="Corrected by edit", cancellation_date=date.today()),
            proxy,
            tenant_id,
        )
        _soft_delete(original)
        replacement_payload = payload.model_copy(update={"payment_number": None})
        replacement = _unwrap(payment_api.create_payment_receipt)(
            request, replacement_payload, proxy, tenant_id
        )
        original.cancellation_reason = f"Corrected by payment {replacement.id}"
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:delete")),
):
    original = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id,
        Payment.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Payment receipt not found.")
    proxy = DeferredCommitSession(db)
    _unwrap(payment_api.cancel_payment_receipt)(
        id,
        PaymentCancel(reason="Deleted by user", cancellation_date=date.today()),
        proxy,
        tenant_id,
    )
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_update_disbursement(
    request: Request,
    id: uuid.UUID,
    payload: BillPaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:update")),
):
    original = db.query(BillPayment).filter(
        BillPayment.id == id,
        BillPayment.tenant_id == tenant_id,
        BillPayment.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Disbursement not found.")

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, BillPayment, original)
    try:
        _unwrap(payment_api.cancel_vendor_payment)(
            id,
            PaymentCancel(reason="Corrected by edit", cancellation_date=date.today()),
            proxy,
            tenant_id,
        )
        _soft_delete(original)
        replacement_payload = payload.model_copy(update={"payment_number": None})
        replacement = _unwrap(payment_api.create_vendor_payment)(
            request, replacement_payload, proxy, tenant_id
        )
        original.cancellation_reason = f"Corrected by payment {replacement.id}"
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_disbursement(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:delete")),
):
    original = db.query(BillPayment).filter(
        BillPayment.id == id,
        BillPayment.tenant_id == tenant_id,
        BillPayment.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Disbursement not found.")
    proxy = DeferredCommitSession(db)
    _unwrap(payment_api.cancel_vendor_payment)(
        id,
        PaymentCancel(reason="Deleted by user", cancellation_date=date.today()),
        proxy,
        tenant_id,
    )
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Sales / purchase returns: POST already posts; correction is PUT/DELETE.
# ---------------------------------------------------------------------------

@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_update_sales_return(
    request: Request,
    id: uuid.UUID,
    payload: SalesReturnCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(SalesReturn).filter(
        SalesReturn.id == id,
        SalesReturn.tenant_id == tenant_id,
        SalesReturn.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Sales return not found.")

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, SalesReturn, original)
    try:
        if original.status != "DRAFT":
            _unwrap(return_api.cancel_sales_return_route)(
                id, proxy, tenant_id, current_user
            )
        _soft_delete(original)
        replacement = _unwrap(return_api.create_sales_return)(
            request, payload, proxy, tenant_id
        )
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_sales_return(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(SalesReturn).filter(
        SalesReturn.id == id,
        SalesReturn.tenant_id == tenant_id,
        SalesReturn.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Sales return not found.")
    proxy = DeferredCommitSession(db)
    if original.status != "DRAFT":
        _unwrap(return_api.cancel_sales_return_route)(id, proxy, tenant_id, current_user)
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_update_purchase_return(
    request: Request,
    id: uuid.UUID,
    payload: PurchaseReturnCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(PurchaseReturn).filter(
        PurchaseReturn.id == id,
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Purchase return not found.")

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, PurchaseReturn, original)
    try:
        if original.status != "DRAFT":
            _unwrap(return_api.cancel_purchase_return_route)(
                id, proxy, tenant_id, current_user
            )
        _soft_delete(original)
        replacement = _unwrap(return_api.create_purchase_return)(
            request, payload, proxy, tenant_id
        )
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_purchase_return(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(PurchaseReturn).filter(
        PurchaseReturn.id == id,
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Purchase return not found.")
    proxy = DeferredCommitSession(db)
    if original.status != "DRAFT":
        _unwrap(return_api.cancel_purchase_return_route)(id, proxy, tenant_id, current_user)
    _soft_delete(original)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# Manual journals: ledger rows are never edited/deleted; public PUT/DELETE
# compose the existing reversal engine.
# ---------------------------------------------------------------------------

def direct_update_manual_journal(
    id: uuid.UUID,
    payload: JournalEntryCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:manual_post")),
):
    original = db.query(JournalEntry).filter(
        JournalEntry.id == id,
        JournalEntry.tenant_id == tenant_id,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Journal entry not found.")
    if original.source_type not in ("MANUAL", "CONTRA"):
        raise HTTPException(400, "Only manual/contra entries can be corrected here.")

    # Both legacy handlers flush. Defer the generic idempotency marker until the
    # replacement exists, then explicitly mark the replacement in the same tx.
    db.info["_defer_idempotency_mark"] = True
    proxy = DeferredCommitSession(db)
    try:
        reversal_response = _unwrap(accounting_api.reverse_manual_journal_entry)(
            id,
            JournalReversalCreate(
                reversal_date=payload.entry_date,
                reason="Corrected by edit",
            ),
            proxy,
            tenant_id,
        )
        replacement_response = _unwrap(accounting_api.create_manual_journal_entry)(
            payload.model_copy(update={"reference_number": None}), proxy, tenant_id
        )
        replacement = db.query(JournalEntry).filter(
            JournalEntry.id == replacement_response.id,
            JournalEntry.tenant_id == tenant_id,
        ).one()
        reversal = db.query(JournalEntry).filter(
            JournalEntry.id == reversal_response.id,
            JournalEntry.tenant_id == tenant_id,
        ).one()
        original.replacement_transaction_id = replacement.id
        replacement.original_transaction_id = original.id
        reversal.reverses_transaction_id = original.id
        _set_replay_resource(db, replacement)
        db.info.pop("_defer_idempotency_mark", None)
        db.commit()
        return _unwrap(accounting_api.get_journal_entry)(replacement.id, db, tenant_id)
    finally:
        db.info.pop("_defer_idempotency_mark", None)


def direct_delete_manual_journal(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:manual_post")),
):
    _unwrap(accounting_api.reverse_manual_journal_entry)(
        id,
        JournalReversalCreate(reversal_date=date.today(), reason="Deleted by user"),
        db,
        tenant_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


_INSTALLED = False


def install_extended_direct_posting_contract() -> None:
    global _INSTALLED
    if _INSTALLED:
        return
    _INSTALLED = True

    # Credit notes
    for path, method in (
        ("/invoices/credit-notes", "POST"),
        ("/invoices/credit-notes/{cn_id}/finalize", "POST"),
        ("/invoices/credit-notes/{cn_id}/cancel", "POST"),
    ):
        _remove_route(invoice_api.router, path, method)
    invoice_api.router.add_api_route(
        "/credit-notes", direct_create_credit_note, methods=["POST"],
        response_model=CreditNoteResponse, status_code=status.HTTP_201_CREATED,
    )
    invoice_api.router.add_api_route(
        "/credit-notes/{id}", direct_update_credit_note, methods=["PUT"],
        response_model=CreditNoteResponse,
    )
    invoice_api.router.add_api_route(
        "/credit-notes/{id}", direct_delete_credit_note, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    # Debit notes
    for path, method in (
        ("/invoices/debit-notes", "POST"),
        ("/invoices/debit-notes/{dn_id}/finalize", "POST"),
        ("/invoices/debit-notes/{dn_id}/cancel", "POST"),
    ):
        _remove_route(invoice_api.router, path, method)
    invoice_api.router.add_api_route(
        "/debit-notes", direct_create_debit_note, methods=["POST"],
        response_model=DebitNoteResponse, status_code=status.HTTP_201_CREATED,
    )
    invoice_api.router.add_api_route(
        "/debit-notes/{id}", direct_update_debit_note, methods=["PUT"],
        response_model=DebitNoteResponse,
    )
    invoice_api.router.add_api_route(
        "/debit-notes/{id}", direct_delete_debit_note, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    # Inventory adjustments
    for path, method in (
        ("/inventory-adjustments", "POST"),
        ("/inventory-adjustments/{id}", "PUT"),
        ("/inventory-adjustments/{id}", "DELETE"),
        ("/inventory-adjustments/{id}/confirm", "POST"),
        ("/inventory-adjustments/{id}/cancel", "POST"),
    ):
        _remove_route(inventory_api.router, path, method)
    inventory_api.router.add_api_route(
        "", direct_create_inventory_adjustment, methods=["POST"],
        response_model=InventoryAdjustmentResponse,
        status_code=status.HTTP_201_CREATED,
    )
    inventory_api.router.add_api_route(
        "/{id}", direct_update_inventory_adjustment, methods=["PUT"],
        response_model=InventoryAdjustmentResponse,
    )
    inventory_api.router.add_api_route(
        "/{id}", direct_delete_inventory_adjustment, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    payment_api.router.add_api_route(
        "/receipts/{id}", direct_update_receipt, methods=["PUT"],
        response_model=PaymentResponse,
    )
    payment_api.router.add_api_route(
        "/receipts/{id}", direct_delete_receipt, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
    payment_api.router.add_api_route(
        "/disbursements/{id}", direct_update_disbursement, methods=["PUT"],
        response_model=BillPaymentResponse,
    )
    payment_api.router.add_api_route(
        "/disbursements/{id}", direct_delete_disbursement, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    return_api.router.add_api_route(
        "/sales/{id}", direct_update_sales_return, methods=["PUT"],
        response_model=SalesReturnResponse,
    )
    return_api.router.add_api_route(
        "/sales/{id}", direct_delete_sales_return, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
    return_api.router.add_api_route(
        "/purchase/{id}", direct_update_purchase_return, methods=["PUT"],
        response_model=PurchaseReturnResponse,
    )
    return_api.router.add_api_route(
        "/purchase/{id}", direct_delete_purchase_return, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    accounting_api.router.add_api_route(
        "/journals/{id}", direct_update_manual_journal, methods=["PUT"],
        response_model=JournalEntryResponse,
    )
    accounting_api.router.add_api_route(
        "/journals/{id}", direct_delete_manual_journal, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
