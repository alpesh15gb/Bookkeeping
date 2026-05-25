from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    ProformaInvoice, ProformaInvoiceLine, Contact, Product, JournalEntry, JournalLine
)
from src.schemas.bill_schemas import (
    ProformaInvoiceCreate, ProformaInvoiceUpdate, ProformaInvoiceResponse, ProformaInvoiceListResponse
)
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/proforma-invoices", tags=["Proforma Invoices"])


@router.post("", response_model=ProformaInvoiceResponse, status_code=status.HTTP_201_CREATED)
def create_proforma_invoice(
    payload: ProformaInvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))  # Reusing invoice:create permission for now
):
    # Verify Customer belongs to active tenant
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")
    
    if contact.contact_type not in ("CUSTOMER", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Customer.")

    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    pi_subtotal = Decimal("0.0000")
    pi_cgst = Decimal("0.0000")
    pi_sgst = Decimal("0.0000")
    pi_igst = Decimal("0.0000")
    pi_utgst = Decimal("0.0000")
    pi_cess = Decimal("0.0000")
    pi_discount = Decimal("0.0000")

    for line in payload.line_items:
        # Check product belongs to tenant
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

        line_subtotal = (line.quantity * line.rate) - line.discount
        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = ProformaInvoiceLine(
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
            discount=line.discount,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
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

        pi_subtotal += db_line.subtotal
        pi_cgst += db_line.cgst_amount
        pi_sgst += db_line.sgst_amount
        pi_igst += db_line.igst_amount
        pi_utgst += db_line.utgst_amount
        pi_cess += db_line.cess_amount
        pi_discount += db_line.discount

    grand_total = pi_subtotal + pi_cgst + pi_sgst + pi_igst + pi_utgst + pi_cess

    pi = ProformaInvoice(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        proforma_number=payload.proforma_number,
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=pi_subtotal,
        discount_total=pi_discount,
        cgst_amount=pi_cgst,
        sgst_amount=pi_sgst,
        igst_amount=pi_igst,
        utgst_amount=pi_utgst,
        cess_amount=pi_cess,
        total=grand_total,
        pos_state_code=payload.pos_state_code,
        lines=db_lines
    )

    db.add(pi)
    db.commit()
    db.refresh(pi)
    return pi


@router.get("", response_model=List[ProformaInvoiceListResponse])
def list_proforma_invoices(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(ProformaInvoice, Contact.name.label("contact_name"))\
        .join(Contact, ProformaInvoice.contact_id == Contact.id)\
        .filter(ProformaInvoice.tenant_id == tenant_id, ProformaInvoice.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for pi, contact_name in results:
        response.append(ProformaInvoiceListResponse(
            id=pi.id,
            proforma_number=pi.proforma_number,
            issue_date=pi.issue_date,
            due_date=pi.due_date,
            status=pi.status,
            total=pi.total,
            contact_name=contact_name,
            created_at=pi.created_at
        ))
    return response


@router.get("/{id}", response_model=ProformaInvoiceResponse)
def get_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")
    return pi


@router.put("/{id}", response_model=ProformaInvoiceResponse)
def update_proforma_invoice(
    id: uuid.UUID,
    payload: ProformaInvoiceUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")

    if pi.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft proforma invoices can be modified.")

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Customer not found in this context.")
        pi.contact_id = payload.contact_id
        
    if payload.proforma_number:
        pi.proforma_number = payload.proforma_number
    if payload.issue_date:
        pi.issue_date = payload.issue_date
    if payload.due_date:
        pi.due_date = payload.due_date
    if payload.pos_state_code:
        pi.pos_state_code = payload.pos_state_code

    if payload.line_items is not None:
        db.query(ProformaInvoiceLine).filter(ProformaInvoiceLine.proforma_invoice_id == id).delete()

        contact = db.query(Contact).filter(Contact.id == pi.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)
        db_lines = []
        pi_subtotal = Decimal("0.0000")
        pi_cgst = Decimal("0.0000")
        pi_sgst = Decimal("0.0000")
        pi_igst = Decimal("0.0000")
        pi_utgst = Decimal("0.0000")
        pi_cess = Decimal("0.0000")
        pi_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            if line_subtotal < 0:
                raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=pi.pos_state_code,
                base_amount=line_subtotal,
                gst_rate=line.gst_rate
            )

            db_line = ProformaInvoiceLine(
                proforma_invoice_id=pi.id,
                product_id=line.product_id,
                quantity=line.quantity,
                rate=line.rate,
                discount=line.discount,
                subtotal=line_subtotal,
                hsn_sac=line.hsn_sac,
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

            pi_subtotal += db_line.subtotal
            pi_cgst += db_line.cgst_amount
            pi_sgst += db_line.sgst_amount
            pi_igst += db_line.igst_amount
            pi_utgst += db_line.utgst_amount
            pi_cess += db_line.cess_amount
            pi_discount += db_line.discount

        pi.subtotal = pi_subtotal
        pi.discount_total = pi_discount
        pi.cgst_amount = pi_cgst
        pi.sgst_amount = pi_sgst
        pi.igst_amount = pi_igst
        pi.utgst_amount = pi_utgst
        pi.cess_amount = pi_cess
        pi.total = pi_subtotal + pi_cgst + pi_sgst + pi_igst + pi_utgst + pi_cess
        pi.lines = db_lines

    db.commit()
    db.refresh(pi)
    return pi


@router.post("/{id}/issue", response_model=ProformaInvoiceResponse)
def issue_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")

    if pi.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft proforma invoices can be issued.")

    # Note: Proforma invoices typically don't create ledger entries upon issuance
    # They serve as quotations that later get converted to sales invoices
    pi.status = "ISSUED"
    db.commit()
    db.refresh(pi)
    return pi


@router.post("/{id}/convert", response_model=ProformaInvoiceResponse)
def convert_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")

    if pi.status != "ISSUED":
        raise HTTPException(status_code=400, detail="Only issued proforma invoices can be converted.")

    # Note: Conversion typically involves creating a sales invoice from the proforma
    # For now, we just mark it as converted
    pi.status = "CONVERTED"
    db.commit()
    db.refresh(pi)
    return pi


@router.post("/{id}/cancel", response_model=ProformaInvoiceResponse)
def cancel_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found.")

    if pi.status in ("CONVERTED", "CANCELLED"):
        raise HTTPException(status_code=400, detail="Cannot convert or cancel already cancelled proforma invoices.")

    pi.status = "CANCELLED"
    db.commit()
    db.refresh(pi)
    return pi