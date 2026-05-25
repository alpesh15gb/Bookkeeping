"""
src/api/v1/credit_notes.py
Full CRUD router for Credit Notes.

Routes:
    POST   /credit-notes          — create a credit note
    GET    /credit-notes          — list with pagination and optional invoice_id filter
    GET    /credit-notes/{id}     — get single credit note
    PUT    /credit-notes/{id}/issue   — issue (DRAFT -> ISSUED)
    PUT    /credit-notes/{id}/cancel  — cancel (ISSUED -> CANCELLED)
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import CreditNote, CreditNoteLine, Invoice, Product
from src.schemas.credit_note_schemas import (
    CreditNoteCreate, CreditNoteResponse, CreditNoteListResponse
)
from src.domains.company.services import NumberingSeriesService
from src.domains.taxation.services import GSTEngine
from src.api.deps import enforce_permission

router = APIRouter(prefix="/credit-notes", tags=["Credit Notes"])


@router.post("", response_model=CreditNoteResponse, status_code=status.HTTP_201_CREATED)
def create_credit_note(
    payload: CreditNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create"))
):
    """Creates a new credit note. Generates an auto-incrementing credit note number."""
    # Validate invoice if provided
    if payload.invoice_id:
        invoice = db.query(Invoice).filter(
            Invoice.id == payload.invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.deleted_at == None
        ).first()
        if not invoice:
            raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    # Determine origin state for GST calculation from POS state code
    origin_state_code = payload.pos_state_code

    db_lines = []
    note_subtotal = Decimal("0.0000")
    note_cgst = Decimal("0.0000")
    note_sgst = Decimal("0.0000")
    note_igst = Decimal("0.0000")
    note_utgst = Decimal("0.0000")
    note_cess = Decimal("0.0000")

    for line in payload.line_items:
        # Validate product belongs to tenant
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(
                status_code=400,
                detail=f"Product with ID {line.product_id} not found in this context."
            )

        line_subtotal = line.quantity * line.rate
        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = CreditNoteLine(
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac or (product.hsn_sac if product else None),
            gst_rate=line.gst_rate,
            cgst_rate=tax_split.cgst_rate,
            cgst_amount=tax_split.cgst_amount,
            sgst_rate=tax_split.sgst_rate,
            sgst_amount=tax_split.sgst_amount,
            igst_rate=tax_split.igst_rate,
            igst_amount=tax_split.igst_amount,
            utgst_rate=tax_split.utgst_rate,
            utgst_amount=tax_split.utgst_amount,
            cess_rate=tax_split.cess_rate,
            cess_amount=tax_split.cess_amount,
            total=tax_split.total_amount
        )
        db_lines.append(db_line)

        note_subtotal += db_line.subtotal
        note_cgst += db_line.cgst_amount
        note_sgst += db_line.sgst_amount
        note_igst += db_line.igst_amount
        note_utgst += db_line.utgst_amount
        note_cess += db_line.cess_amount

    grand_total = note_subtotal + note_cgst + note_sgst + note_igst + note_utgst + note_cess

    # Generate auto-increment number
    credit_note_number = NumberingSeriesService.generate_next_number(db, tenant_id, "CREDIT_NOTE")

    credit_note = CreditNote(
        tenant_id=tenant_id,
        invoice_id=payload.invoice_id,
        credit_note_number=credit_note_number,
        issue_date=payload.issue_date,
        reason=payload.reason,
        status="DRAFT",
        subtotal=note_subtotal,
        cgst_amount=note_cgst,
        sgst_amount=note_sgst,
        igst_amount=note_igst,
        utgst_amount=note_utgst,
        cess_amount=note_cess,
        round_off=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        total=grand_total,
        lines=db_lines
    )

    db.add(credit_note)
    db.commit()
    db.refresh(credit_note)
    return credit_note


@router.get("", response_model=List[CreditNoteListResponse])
def list_credit_notes(
    page: int = 1,
    limit: int = 50,
    invoice_id: Optional[uuid.UUID] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:view"))
):
    """Lists credit notes for the active tenant with pagination and optional invoice filter."""
    offset = (page - 1) * limit
    q = db.query(CreditNote).filter(
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    )
    if invoice_id:
        q = q.filter(CreditNote.invoice_id == invoice_id)

    return q.order_by(CreditNote.issue_date.desc()).offset(offset).limit(limit).all()


@router.get("/{id}", response_model=CreditNoteResponse)
def get_credit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:view"))
):
    """Retrieves a single credit note by ID."""
    credit_note = db.query(CreditNote).filter(
        CreditNote.id == id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not credit_note:
        raise HTTPException(status_code=404, detail="Credit note not found in this company context.")
    return credit_note


@router.put("/{id}/issue", response_model=CreditNoteResponse)
def issue_credit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create"))
):
    """Issues a credit note, transitioning it from DRAFT to ISSUED status."""
    credit_note = db.query(CreditNote).filter(
        CreditNote.id == id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not credit_note:
        raise HTTPException(status_code=404, detail="Credit note not found in this company context.")

    if credit_note.status != "DRAFT":
        raise HTTPException(
            status_code=400,
            detail=f"Only DRAFT credit notes can be issued. Current status: {credit_note.status}"
        )

    credit_note.status = "ISSUED"
    db.commit()
    db.refresh(credit_note)
    return credit_note


@router.put("/{id}/cancel", response_model=CreditNoteResponse)
def cancel_credit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create"))
):
    """Cancels an issued credit note, transitioning it from ISSUED to CANCELLED status."""
    credit_note = db.query(CreditNote).filter(
        CreditNote.id == id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not credit_note:
        raise HTTPException(status_code=404, detail="Credit note not found in this company context.")

    if credit_note.status != "ISSUED":
        raise HTTPException(
            status_code=400,
            detail=f"Only ISSUED credit notes can be cancelled. Current status: {credit_note.status}"
        )

    credit_note.status = "CANCELLED"
    credit_note.deleted_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(credit_note)
    return credit_note
