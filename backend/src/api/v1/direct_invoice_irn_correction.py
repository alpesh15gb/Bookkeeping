"""Narrow compliance wrapper for direct invoice Edit/Delete.

An IRN is permanent audit data and must never be cleared.  Before statutory
cancellation, an IRN-bearing invoice cannot be edited/deleted.  Once the IRP
e-invoice status is CANCELLED, the normal accounting correction (reversal +
replacement or reversal + soft-delete) may proceed while the original IRN
remains stored on the historical document.
"""

import uuid
from datetime import datetime, timezone

from fastapi import Depends, HTTPException, Request, Response, status

from src.api.deps import enforce_permission, get_current_user
from src.core.database import get_db_session
from src.infrastructure.database.models import Invoice, User
from src.schemas.document import InvoiceCreate, InvoiceResponse, InvoiceUpdate
from src.api.v1 import invoices as invoice_api
from src.api.v1.direct_posting_contract import (
    DeferredCommitSession,
    _begin_replacement,
    _end_replacement,
    _invoice_discount_rate,
    _invoice_lines,
    _remove_route,
    _unwrap,
    direct_delete_invoice,
    direct_update_invoice,
)


def _cancelled_irn(invoice: Invoice) -> bool:
    return bool(invoice.irn) and invoice.e_invoice_status == "CANCELLED"


def direct_update_cancelled_irn_invoice(
    request: Request,
    id: uuid.UUID,
    payload: InvoiceUpdate,
    db=Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Invoice not found in this company context.")

    # All ordinary invoices, including an active IRN, retain the standard
    # handler.  It blocks an active IRN and handles every non-IRN correction.
    if not _cancelled_irn(original):
        return direct_update_invoice(
            request, id, payload, db, tenant_id, current_user
        )

    if original.source_document_type:
        raise HTTPException(
            409, "Correct source-derived invoices from their originating document."
        )
    if original.status == "PAID":
        raise HTTPException(
            409, "Reverse applied receipt(s) before editing this invoice."
        )

    replacement_payload = InvoiceCreate(
        contact_id=payload.contact_id or original.contact_id,
        invoice_number=None,
        issue_date=payload.issue_date or original.issue_date,
        due_date=payload.due_date or original.due_date,
        pos_state_code=payload.pos_state_code or original.pos_state_code,
        line_items=payload.line_items or _invoice_lines(original),
        discount_rate=(
            payload.discount_rate
            if payload.discount_rate is not None
            else _invoice_discount_rate(original)
        ),
        shipping_charges=(
            payload.shipping_charges
            if payload.shipping_charges is not None
            else original.shipping_charges
        ),
        notes=payload.notes if payload.notes is not None else original.notes,
        terms_and_conditions=(
            payload.terms_and_conditions
            if payload.terms_and_conditions is not None
            else original.terms_and_conditions
        ),
        reference_number=(
            payload.reference_number
            if payload.reference_number is not None
            else original.reference_number
        ),
        sales_person_id=(
            payload.sales_person_id
            if payload.sales_person_id is not None
            else original.sales_person_id
        ),
        is_gst_inclusive=(
            payload.is_gst_inclusive
            if payload.is_gst_inclusive is not None
            else original.is_gst_inclusive
        ),
        is_rcm=payload.is_rcm if payload.is_rcm is not None else original.is_rcm,
        supply_type=payload.supply_type or original.supply_type,
        currency=payload.currency or original.currency,
        exchange_rate=payload.exchange_rate or original.exchange_rate,
        tds_rate=payload.tds_rate if payload.tds_rate is not None else original.tds_rate,
        tcs_rate=payload.tcs_rate if payload.tcs_rate is not None else original.tcs_rate,
        post_on_create=True,
    )

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, Invoice, original)
    try:
        if original.status == "SENT":
            original.status = "POSTED"
        _unwrap(invoice_api.cancel_invoice)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)
        replacement = _unwrap(invoice_api.create_invoice)(
            request, replacement_payload, db, tenant_id
        )
        return replacement
    finally:
        _end_replacement(db)


def direct_delete_cancelled_irn_invoice(
    id: uuid.UUID,
    db=Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Invoice not found.")

    if not _cancelled_irn(original):
        return direct_delete_invoice(id, db, tenant_id, current_user)
    if original.status == "PAID":
        raise HTTPException(
            409, "Reverse applied receipt(s) before deleting this invoice."
        )

    proxy = DeferredCommitSession(db)
    if original.status == "SENT":
        original.status = "POSTED"
    _unwrap(invoice_api.cancel_invoice)(id, proxy, tenant_id, current_user)
    original.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def install_cancelled_irn_direct_correction() -> None:
    # Replace only the public PUT/DELETE route bindings.  Statutory
    # `/e-invoice/cancel` remains public and unchanged.
    _remove_route(invoice_api.router, "/invoices/{id}", "PUT")
    _remove_route(invoice_api.router, "/invoices/{id}", "DELETE")
    invoice_api.router.add_api_route(
        "/{id}",
        direct_update_cancelled_irn_invoice,
        methods=["PUT"],
        response_model=InvoiceResponse,
    )
    invoice_api.router.add_api_route(
        "/{id}",
        direct_delete_cancelled_irn_invoice,
        methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
