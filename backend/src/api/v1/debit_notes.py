"""
src/api/v1/debit_notes.py
Full CRUD router for Debit Notes.

Routes:
    POST   /debit-notes          — create a debit note
    GET    /debit-notes          — list with pagination and optional invoice_id filter
    GET    /debit-notes/{id}     — get single debit note
    PUT    /debit-notes/{id}/issue   — issue (DRAFT -> ISSUED)
    PUT    /debit-notes/{id}/cancel  — cancel (ISSUED -> CANCELLED)
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import DebitNote, DebitNoteLine, Invoice, Product
from src.schemas.debit_note_schemas import (
    DebitNoteCreate, DebitNoteResponse, DebitNoteListResponse
)
from src.domains.company.services import NumberingSeriesService, resolve_origin_state_code

@router.post("", response_model=DebitNoteResponse, status_code=status.HTTP_201_CREATED)
def create_debit_note(
    payload: DebitNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create"))
):
    """Creates a new debit note. Generates an auto-incrementing debit note number."""
    # Validate invoice if provided
    if payload.invoice_id:
        invoice = db.query(Invoice).filter(
            Invoice.id == payload.invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.deleted_at == None
        ).first()
        if not invoice:
            raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    # Determine origin state for GST calculation
    origin_state_code = resolve_origin_state_code(db, tenant_id)

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

        db_line = DebitNoteLine(
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
    debit_note_number = NumberingSeriesService.generate_next_number(db, tenant_id, "DEBIT_NOTE")

    debit_note = DebitNote(
        tenant_id=tenant_id,
        invoice_id=payload.invoice_id,
        debit_note_number=debit_note_number,
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

    db.add(debit_note)
    db.commit()
    db.refresh(debit_note)
    return debit_note


@router.get("", response_model=List[DebitNoteListResponse])
def list_debit_notes(
    page: int = 1,
    limit: int = 50,
    invoice_id: Optional[uuid.UUID] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:view"))
):
    """Lists debit notes for the active tenant with pagination and optional invoice filter."""
    offset = (page - 1) * limit
    q = db.query(DebitNote).filter(
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    )
    if invoice_id:
        q = q.filter(DebitNote.invoice_id == invoice_id)

    return q.order_by(DebitNote.issue_date.desc()).offset(offset).limit(limit).all()


@router.get("/{id}", response_model=DebitNoteResponse)
def get_debit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:view"))
):
    """Retrieves a single debit note by ID."""
    debit_note = db.query(DebitNote).filter(
        DebitNote.id == id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not debit_note:
        raise HTTPException(status_code=404, detail="Debit note not found in this company context.")
    return debit_note


@router.put("/{id}/issue", response_model=DebitNoteResponse)
def issue_debit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create"))
):
    """Issues a debit note, transitioning it from DRAFT to ISSUED status."""
    debit_note = db.query(DebitNote).filter(
        DebitNote.id == id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not debit_note:
        raise HTTPException(status_code=404, detail="Debit note not found in this company context.")

    if debit_note.status != "DRAFT":
        raise HTTPException(
            status_code=400,
            detail=f"Only DRAFT debit notes can be issued. Current status: {debit_note.status}"
        )

    debit_note.status = "ISSUED"
    db.commit()
    db.refresh(debit_note)
    return debit_note


@router.put("/{id}/cancel", response_model=DebitNoteResponse)
def cancel_debit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("credit_note:create"))
):
    """Cancels an issued debit note, transitioning it from ISSUED to CANCELLED status."""
    debit_note = db.query(DebitNote).filter(
        DebitNote.id == id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not debit_note:
        raise HTTPException(status_code=404, detail="Debit note not found in this company context.")

    if debit_note.status != "ISSUED":
        raise HTTPException(
            status_code=400,
            detail=f"Only ISSUED debit notes can be cancelled. Current status: {debit_note.status}"
        )

    debit_note.status = "CANCELLED"
    debit_note.deleted_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(debit_note)
    return debit_note
