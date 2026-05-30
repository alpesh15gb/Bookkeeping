from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date, datetime, timezone


from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Contact, Product, Payment, PaymentAllocation, Account, JournalEntry, JournalLine,
    CreditNote, CreditNoteLine, DebitNote, DebitNoteLine, TenantSetting, BankingProfile, Tenant
)
from src.schemas.document import (
    InvoiceCreate, InvoiceUpdate, InvoiceResponse, InvoiceListResponse,
    PaginatedInvoiceResponse, PaymentCreate,
    InvoicePreviewRequest,
    CreditNoteCreate, CreditNoteResponse, CreditNoteListResponse,
    DebitNoteCreate, DebitNoteResponse, DebitNoteListResponse
)
from src.schemas.einvoice_schemas import EInvoiceResponse, EInvoiceCancelRequest, EInvoiceCancelResponse
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.company.services import NumberingSeriesService, resolve_origin_state_code
from src.api.deps import enforce_permission

router = APIRouter(prefix="/invoices", tags=["Invoices"])

@router.post("", response_model=InvoiceResponse, status_code=status.HTTP_201_CREATED)
def create_invoice(
    payload: InvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    # Verify Customer belongs to active tenant
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")

    # 1. Sequence Auto-Generation
    invoice_number = payload.invoice_number
    if not invoice_number:
        invoice_number = NumberingSeriesService.generate_next_number(db, tenant_id, "INVOICE")

    # 2. Duplicate Check
    dup = db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.invoice_number == invoice_number,
        Invoice.deleted_at == None
    ).first()
    if dup:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invoice number {invoice_number} already exists."
        )

    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    inv_subtotal = Decimal("0.0000")
    inv_cgst = Decimal("0.0000")
    inv_sgst = Decimal("0.0000")
    inv_igst = Decimal("0.0000")
    inv_utgst = Decimal("0.0000")
    inv_cess = Decimal("0.0000")
    inv_discount = Decimal("0.0000")

    for line in payload.line_items:
        # Check product matches tenant context
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this company context.")

        line_subtotal = (line.quantity * line.rate) - line.discount
        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = InvoiceLine(
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

        inv_subtotal += db_line.subtotal
        inv_cgst += db_line.cgst_amount
        inv_sgst += db_line.sgst_amount
        inv_igst += db_line.igst_amount
        inv_utgst += db_line.utgst_amount
        inv_cess += db_line.cess_amount
        inv_discount += db_line.discount

    # 3. Apply header-level discount and shipping charges
    header_discount_rate = payload.discount_rate or Decimal("0.00")
    header_shipping = payload.shipping_charges or Decimal("0.0000")
    
    discount_amount = (inv_subtotal * header_discount_rate / Decimal("100.00")).quantize(Decimal("0.0001"))
    adjusted_subtotal = inv_subtotal - discount_amount
    
    # Recalculate taxes based on adjusted subtotal (proportional)
    tax_multiplier = Decimal("1.00") if inv_subtotal == 0 else adjusted_subtotal / inv_subtotal
    final_cgst = (inv_cgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_sgst = (inv_sgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_igst = (inv_igst * tax_multiplier).quantize(Decimal("0.0001"))
    final_utgst = (inv_utgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_cess = (inv_cess * tax_multiplier).quantize(Decimal("0.0001"))
    
    # Round-off adjustment calculations
    raw_total = adjusted_subtotal + final_cgst + final_sgst + final_igst + final_utgst + final_cess + header_shipping
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    invoice = Invoice(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        invoice_number=invoice_number,
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=inv_subtotal,
        discount_total=discount_amount,
        cgst_amount=final_cgst,
        sgst_amount=final_sgst,
        igst_amount=final_igst,
        utgst_amount=final_utgst,
        cess_amount=final_cess,
        round_off=round_off,
        shipping_charges=header_shipping,
        total=rounded_total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        e_invoice_status="PENDING",
        lines=db_lines
    )

    db.add(invoice)
    db.commit()
    db.refresh(invoice)
    return invoice

@router.get("", response_model=PaginatedInvoiceResponse)
def list_invoices(
    page: int = 1,
    limit: int = 50,
    search: Optional[str] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    q = db.query(Invoice, Contact.name.label("contact_name"))\
        .options(joinedload(Invoice.contact))\
        .join(Contact, Invoice.contact_id == Contact.id)\
        .filter(Invoice.tenant_id == tenant_id, Invoice.deleted_at == None)

    if search:
        q = q.filter(
            Invoice.invoice_number.ilike(f"%{search}%") |
            Contact.name.ilike(f"%{search}%")
        )

    if status and status.upper() != "ALL":
        if status.upper() == "PAID":
            q = q.filter(Invoice.status == "PAID")
        elif status.upper() == "CANCELLED":
            q = q.filter(Invoice.status == "CANCELLED")
        elif status.upper() == "POSTED":
            q = q.filter(Invoice.status == "POSTED")
        elif status.upper() == "PARTIALLY_PAID":
            q = q.filter(Invoice.status == "PARTIALLY_PAID")
        else:
            q = q.filter(Invoice.status == status.upper())

    total = q.count()
    results = q.offset(offset).limit(limit).all()

    items = []
    for inv, contact_name in results:
        items.append(InvoiceListResponse(
            id=inv.id,
            invoice_number=inv.invoice_number,
            issue_date=inv.issue_date,
            due_date=inv.due_date,
            status=inv.status,
            total=inv.total,
            amount_paid=inv.amount_paid,
            contact_name=contact_name,
            created_at=inv.created_at
        ))
    return PaginatedInvoiceResponse(items=items, total=total, page=page, limit=limit)

@router.post("/preview", response_model=InvoiceResponse, tags=["Invoices"])
def preview_invoice(
    payload: InvoicePreviewRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    """
    Returns a computed preview of an invoice without creating it.
    Useful for frontend live preview before submission.
    Contact resolution is skipped since preview doesn't require it.
    """
    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    inv_subtotal = Decimal("0.0000")
    inv_cgst = Decimal("0.0000")
    inv_sgst = Decimal("0.0000")
    inv_igst = Decimal("0.0000")
    inv_utgst = Decimal("0.0000")
    inv_cess = Decimal("0.0000")
    inv_discount = Decimal("0.0000")

    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found.")

        line_subtotal = (line.quantity * line.rate) - line.discount
        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = InvoiceLine(
            id=uuid.UUID(int=0),
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

        inv_subtotal += db_line.subtotal
        inv_cgst += db_line.cgst_amount
        inv_sgst += db_line.sgst_amount
        inv_igst += db_line.igst_amount
        inv_utgst += db_line.utgst_amount
        inv_cess += db_line.cess_amount
        inv_discount += db_line.discount

    header_discount_rate = payload.discount_rate or Decimal("0.00")
    header_shipping = payload.shipping_charges or Decimal("0.0000")
    
    discount_amount = (inv_subtotal * header_discount_rate / Decimal("100.00")).quantize(Decimal("0.0001"))
    adjusted_subtotal = inv_subtotal - discount_amount
    
    tax_multiplier = Decimal("1.00") if inv_subtotal == 0 else adjusted_subtotal / inv_subtotal
    final_cgst = (inv_cgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_sgst = (inv_sgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_igst = (inv_igst * tax_multiplier).quantize(Decimal("0.0001"))
    final_utgst = (inv_utgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_cess = (inv_cess * tax_multiplier).quantize(Decimal("0.0001"))
    
    raw_total = adjusted_subtotal + final_cgst + final_sgst + final_igst + final_utgst + final_cess + header_shipping
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    preview_invoice = Invoice(
        id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
        tenant_id=tenant_id,
        contact_id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
        invoice_number="PREVIEW",
        issue_date=date.today(),
        due_date=date.today(),
        status="DRAFT",
        subtotal=inv_subtotal,
        discount_total=discount_amount,
        cgst_amount=final_cgst,
        sgst_amount=final_sgst,
        igst_amount=final_igst,
        utgst_amount=final_utgst,
        cess_amount=final_cess,
        round_off=round_off,
        total=rounded_total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        e_invoice_status="PENDING",
        lines=db_lines,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )

    return preview_invoice


# ==========================================
# CREDIT NOTES ROUTERS â€” statuses: DRAFT â†’ POSTED â†’ CANCELLED
# ==========================================

@router.post("/credit-notes", response_model=CreditNoteResponse, status_code=status.HTTP_201_CREATED)
def create_credit_note(
    payload: CreditNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    if payload.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == payload.invoice_id, Invoice.tenant_id == tenant_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="Invoice not found.")

    cn_number = payload.credit_note_number
    if not cn_number:
        cn_number = f"CN-{uuid.uuid4().hex[:6].upper()}"

    origin_state = resolve_origin_state_code(db, tenant_id)
    place_of_supply = inv.pos_state_code if payload.invoice_id and inv else origin_state

    db_lines = []
    subtotal = Decimal("0.0000")
    cgst = Decimal("0.0000")
    sgst = Decimal("0.0000")
    igst = Decimal("0.0000")
    utgst = Decimal("0.0000")
    cess = Decimal("0.0000")

    for line in payload.line_items:
        line_subtotal = line.quantity * line.rate
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = CreditNoteLine(
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
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

        subtotal += line_subtotal
        cgst += tax_split.cgst_amount
        sgst += tax_split.sgst_amount
        igst += tax_split.igst_amount
        utgst += tax_split.utgst_amount
        cess += tax_split.cess_amount

    raw_total = subtotal + cgst + sgst + igst + utgst + cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    cn = CreditNote(
        tenant_id=tenant_id,
        invoice_id=payload.invoice_id,
        credit_note_number=cn_number,
        issue_date=payload.issue_date,
        reason=payload.reason,
        status="DRAFT",
        subtotal=subtotal,
        cgst_amount=cgst,
        sgst_amount=sgst,
        igst_amount=igst,
        utgst_amount=utgst,
        cess_amount=cess,
        round_off=round_off,
        pos_state_code=place_of_supply,
        total=rounded_total,
        lines=db_lines
    )
    db.add(cn)
    db.commit()
    db.refresh(cn)
    return cn


@router.post("/credit-notes/preview", response_model=CreditNoteResponse)
def preview_credit_note(
    payload: CreditNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    inv = None
    if payload.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == payload.invoice_id, Invoice.tenant_id == tenant_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="Invoice not found.")

    origin_state = resolve_origin_state_code(db, tenant_id)
    place_of_supply = inv.pos_state_code if payload.invoice_id and inv else origin_state

    db_lines = []
    subtotal = Decimal("0.0000")
    cgst = Decimal("0.0000")
    sgst = Decimal("0.0000")
    igst = Decimal("0.0000")
    utgst = Decimal("0.0000")
    cess = Decimal("0.0000")

    for line in payload.line_items:
        line_subtotal = line.quantity * line.rate
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = CreditNoteLine(
            id=uuid.UUID(int=0),
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
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

        subtotal += line_subtotal
        cgst += tax_split.cgst_amount
        sgst += tax_split.sgst_amount
        igst += tax_split.igst_amount
        utgst += tax_split.utgst_amount
        cess += tax_split.cess_amount

    raw_total = subtotal + cgst + sgst + igst + utgst + cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    cn = CreditNote(
        id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
        tenant_id=tenant_id,
        invoice_id=payload.invoice_id,
        credit_note_number="PREVIEW",
        issue_date=payload.issue_date,
        reason=payload.reason,
        status="DRAFT",
        subtotal=subtotal,
        cgst_amount=cgst,
        sgst_amount=sgst,
        igst_amount=igst,
        utgst_amount=utgst,
        cess_amount=cess,
        round_off=round_off,
        pos_state_code=place_of_supply,
        total=rounded_total,
        lines=db_lines,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    return cn


@router.get("/credit-notes", response_model=List[CreditNoteListResponse])
def list_credit_notes(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    notes = db.query(CreditNote).options(
        joinedload(CreditNote.invoice).joinedload(Invoice.contact)
    ).filter(
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).all()
    return [
        CreditNoteListResponse(
            id=cn.id,
            credit_note_number=cn.credit_note_number,
            issue_date=cn.issue_date,
            status=cn.status,
            total=cn.total,
            reason=cn.reason,
            created_at=cn.created_at,
            invoice_number=cn.invoice.invoice_number if cn.invoice else None,
            contact_name=cn.invoice.contact.name if cn.invoice and cn.invoice.contact else None,
        )
        for cn in notes
    ]

@router.get("/credit-notes/{cn_id}", response_model=CreditNoteResponse)
def get_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")
    return cn

@router.post("/credit-notes/{cn_id}/finalize", response_model=CreditNoteResponse)
def finalize_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")

    if cn.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft Credit Notes can be finalized.")

    contact_id = cn.invoice.contact_id if cn.invoice else None
    if not contact_id:
        raise HTTPException(status_code=400, detail="Credit Note must be linked to a contact or invoice for finalization.")
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if cn.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_credit_note_posting(
        tenant_id=tenant_id,
        credit_note_id=cn.id,
        credit_note_number=cn.credit_note_number,
        issue_date=cn.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=cn.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=cn.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=cn.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=cn.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=cn.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=cn.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=cn.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    cn.status = "POSTED"
    db.commit()
    db.refresh(cn)
    return cn


@router.post("/credit-notes/{cn_id}/cancel", response_model=CreditNoteResponse)
def cancel_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")

    if cn.status != "POSTED":
        raise HTTPException(status_code=400, detail="Only posted Credit Notes can be cancelled.")

    contact_id = cn.invoice.contact_id if cn.invoice else None
    if not contact_id:
        raise HTTPException(status_code=400, detail="Credit Note must be linked to a contact or invoice for cancellation.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if cn.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_credit_note_reversal_posting(
        tenant_id=tenant_id,
        credit_note_id=cn.id,
        credit_note_number=cn.credit_note_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=cn.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=cn.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=cn.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=cn.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=cn.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=cn.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=cn.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    cn.status = "CANCELLED"
    db.commit()
    db.refresh(cn)
    return cn


# ==========================================
# DEBIT NOTES ROUTERS â€” statuses: DRAFT â†’ POSTED â†’ CANCELLED
# ==========================================

@router.get("/debit-notes", response_model=List[DebitNoteListResponse])
def list_debit_notes(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    notes = db.query(DebitNote).options(
        joinedload(DebitNote.invoice).joinedload(Invoice.contact)
    ).filter(
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).all()
    return [
        DebitNoteListResponse(
            id=dn.id,
            debit_note_number=dn.debit_note_number,
            issue_date=dn.issue_date,
            status=dn.status,
            total=dn.total,
            reason=dn.reason,
            created_at=dn.created_at,
        )
        for dn in notes
    ]


@router.get("/debit-notes/{dn_id}", response_model=DebitNoteResponse)
def get_debit_note(
    dn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    dn = db.query(DebitNote).filter(
        DebitNote.id == dn_id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not dn:
        raise HTTPException(status_code=404, detail="Debit Note not found.")
    return dn


@router.post("/debit-notes", response_model=DebitNoteResponse, status_code=status.HTTP_201_CREATED)
def create_debit_note(
    payload: DebitNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    if payload.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == payload.invoice_id, Invoice.tenant_id == tenant_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="Invoice not found.")

    dn_number = payload.debit_note_number
    if not dn_number:
        dn_number = f"DN-{uuid.uuid4().hex[:6].upper()}"

    origin_state = resolve_origin_state_code(db, tenant_id)
    place_of_supply = inv.pos_state_code if payload.invoice_id and inv else origin_state

    db_lines = []
    subtotal = Decimal("0.0000")
    cgst = Decimal("0.0000")
    sgst = Decimal("0.0000")
    igst = Decimal("0.0000")
    utgst = Decimal("0.0000")
    cess = Decimal("0.0000")

    for line in payload.line_items:
        line_subtotal = line.quantity * line.rate
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = DebitNoteLine(
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
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

        subtotal += line_subtotal
        cgst += tax_split.cgst_amount
        sgst += tax_split.sgst_amount
        igst += tax_split.igst_amount
        utgst += tax_split.utgst_amount
        cess += tax_split.cess_amount

    raw_total = subtotal + cgst + sgst + igst + utgst + cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    dn = DebitNote(
        tenant_id=tenant_id,
        invoice_id=payload.invoice_id,
        debit_note_number=dn_number,
        issue_date=payload.issue_date,
        reason=payload.reason,
        status="DRAFT",
        subtotal=subtotal,
        cgst_amount=cgst,
        sgst_amount=sgst,
        igst_amount=igst,
        utgst_amount=utgst,
        cess_amount=cess,
        round_off=round_off,
        pos_state_code=place_of_supply,
        total=rounded_total,
        lines=db_lines
    )
    db.add(dn)
    db.commit()
    db.refresh(dn)
    return dn


@router.post("/debit-notes/preview", response_model=DebitNoteResponse)
def preview_debit_note(
    payload: DebitNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    inv = None
    if payload.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == payload.invoice_id, Invoice.tenant_id == tenant_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="Invoice not found.")

    origin_state = resolve_origin_state_code(db, tenant_id)
    place_of_supply = inv.pos_state_code if payload.invoice_id and inv else origin_state

    db_lines = []
    subtotal = Decimal("0.0000")
    cgst = Decimal("0.0000")
    sgst = Decimal("0.0000")
    igst = Decimal("0.0000")
    utgst = Decimal("0.0000")
    cess = Decimal("0.0000")

    for line in payload.line_items:
        line_subtotal = line.quantity * line.rate
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=line.gst_rate
        )

        db_line = DebitNoteLine(
            id=uuid.UUID(int=0),
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
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

        subtotal += line_subtotal
        cgst += tax_split.cgst_amount
        sgst += tax_split.sgst_amount
        igst += tax_split.igst_amount
        utgst += tax_split.utgst_amount
        cess += tax_split.cess_amount

    raw_total = subtotal + cgst + sgst + igst + utgst + cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    dn = DebitNote(
        id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
        tenant_id=tenant_id,
        invoice_id=payload.invoice_id,
        debit_note_number="PREVIEW",
        issue_date=payload.issue_date,
        reason=payload.reason,
        status="DRAFT",
        subtotal=subtotal,
        cgst_amount=cgst,
        sgst_amount=sgst,
        igst_amount=igst,
        utgst_amount=utgst,
        cess_amount=cess,
        round_off=round_off,
        pos_state_code=place_of_supply,
        total=rounded_total,
        lines=db_lines,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    return dn


@router.post("/debit-notes/{dn_id}/finalize", response_model=DebitNoteResponse)
def finalize_debit_note(
    dn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    dn = db.query(DebitNote).filter(
        DebitNote.id == dn_id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not dn:
        raise HTTPException(status_code=404, detail="Debit Note not found.")

    if dn.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft Debit Notes can be finalized.")

    contact_id = dn.invoice.contact_id if dn.invoice else None
    if not contact_id:
        raise HTTPException(status_code=400, detail="Debit Note must be linked to a contact or invoice for finalization.")
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if dn.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_debit_note_posting(
        tenant_id=tenant_id,
        debit_note_id=dn.id,
        debit_note_number=dn.debit_note_number,
        issue_date=dn.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=dn.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=dn.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=dn.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=dn.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=dn.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=dn.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=dn.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    dn.status = "POSTED"
    db.commit()
    db.refresh(dn)
    return dn


@router.post("/debit-notes/{dn_id}/cancel", response_model=DebitNoteResponse)
def cancel_debit_note(
    dn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    dn = db.query(DebitNote).filter(
        DebitNote.id == dn_id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not dn:
        raise HTTPException(status_code=404, detail="Debit Note not found.")

    if dn.status != "POSTED":
        raise HTTPException(status_code=400, detail="Only posted Debit Notes can be cancelled.")

    contact_id = dn.invoice.contact_id if dn.invoice else None
    if not contact_id:
        raise HTTPException(status_code=400, detail="Debit Note must be linked to a contact or invoice for cancellation.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if dn.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_debit_note_reversal_posting(
        tenant_id=tenant_id,
        debit_note_id=dn.id,
        debit_note_number=dn.debit_note_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=dn.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=dn.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=dn.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=dn.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=dn.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=dn.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=dn.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    dn.status = "CANCELLED"
    db.commit()
    db.refresh(dn)
    return dn

# ==========================================
# INVOICE ROUTES â€” statuses: DRAFT â†’ POSTED â†’ PARTIALLY_PAID/PAID â†’ CANCELLED
# ==========================================

@router.post("/bulk-delete")
def bulk_delete_invoices(
    payload: dict,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
):
    """Bulk delete multiple invoices."""
    ids = payload.get("ids", [])
    if not ids:
        raise HTTPException(status_code=400, detail="No IDs provided.")

    deleted = 0
    for invoice_id in ids:
        invoice = db.query(Invoice).filter(
            Invoice.id == invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.deleted_at == None,
        ).first()
        if invoice and invoice.status == "DRAFT":
            invoice.deleted_at = datetime.now(timezone.utc)
            deleted += 1

    db.commit()
    return {"deleted": deleted}


@router.get("/{id}", response_model=InvoiceResponse)
def get_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")
    return invoice

@router.put("/{id}", response_model=InvoiceResponse)
def update_invoice(
    id: uuid.UUID,
    payload: InvoiceUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    if invoice.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft invoices can be edited."
        )

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Customer not found in this context.")
        invoice.contact_id = payload.contact_id

    if payload.invoice_number:
        invoice.invoice_number = payload.invoice_number
    if payload.issue_date:
        invoice.issue_date = payload.issue_date
    if payload.due_date:
        invoice.due_date = payload.due_date
    if payload.pos_state_code:
        invoice.pos_state_code = payload.pos_state_code

    if payload.line_items is not None:
        origin_state_code = resolve_origin_state_code(db, tenant_id)
        
        existing_lines = db.query(InvoiceLine).filter(InvoiceLine.invoice_id == id).all()
        existing_by_id = {str(line.id): line for line in existing_lines if line.id}
        existing_by_key = {(line.product_id, line.hsn_sac, line.gst_rate, line.rate): line for line in existing_lines}

        kept_ids = set()
        db_lines = []
        inv_subtotal = Decimal("0.0000")
        inv_cgst = Decimal("0.0000")
        inv_sgst = Decimal("0.0000")
        inv_igst = Decimal("0.0000")
        inv_utgst = Decimal("0.0000")
        inv_cess = Decimal("0.0000")
        inv_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=invoice.pos_state_code,
                base_amount=line_subtotal,
                gst_rate=line.gst_rate
            )

            db_line = None
            if line.id and str(line.id) in existing_by_id:
                db_line = existing_by_id[str(line.id)]
            if db_line is None:
                key = (line.product_id, line.hsn_sac, line.gst_rate, line.rate)
                db_line = existing_by_key.get(key)

            if db_line is not None:
                kept_ids.add(str(db_line.id))
                db_line.quantity = line.quantity
                db_line.rate = line.rate
                db_line.discount = line.discount
                db_line.subtotal = line_subtotal
                db_line.hsn_sac = line.hsn_sac
                db_line.gst_rate = line.gst_rate
                db_line.cgst_rate = tax_split.cgst_rate
                db_line.cgst_amount = tax_split.cgst_amount
                db_line.sgst_rate = tax_split.sgst_rate
                db_line.sgst_amount = tax_split.sgst_amount
                db_line.igst_rate = tax_split.igst_rate
                db_line.igst_amount = tax_split.igst_amount
                db_line.utgst_rate = tax_split.utgst_rate
                db_line.utgst_amount = tax_split.utgst_amount
                db_line.cess_rate = tax_split.cess_rate
                db_line.cess_amount = tax_split.cess_amount
                db_line.total = tax_split.total_amount
            else:
                db_line = InvoiceLine(
                    invoice_id=invoice.id,
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
                db.add(db_line)
            
            db_lines.append(db_line)
            if db_line.id:
                kept_ids.add(str(db_line.id))

            inv_subtotal += db_line.subtotal
            inv_cgst += db_line.cgst_amount
            inv_sgst += db_line.sgst_amount
            inv_igst += db_line.igst_amount
            inv_utgst += db_line.utgst_amount
            inv_cess += db_line.cess_amount
            inv_discount += db_line.discount

        for existing_line in existing_lines:
            if str(existing_line.id) not in kept_ids:
                db.delete(existing_line)

        header_discount_rate = payload.discount_rate or Decimal("0.00")
        header_shipping = payload.shipping_charges or Decimal("0.0000")
        
        discount_amount = (inv_subtotal * header_discount_rate / Decimal("100.00")).quantize(Decimal("0.0001"))
        adjusted_subtotal = inv_subtotal - discount_amount
        
        tax_multiplier = Decimal("1.00") if inv_subtotal == 0 else adjusted_subtotal / inv_subtotal
        final_cgst = (inv_cgst * tax_multiplier).quantize(Decimal("0.0001"))
        final_sgst = (inv_sgst * tax_multiplier).quantize(Decimal("0.0001"))
        final_igst = (inv_igst * tax_multiplier).quantize(Decimal("0.0001"))
        final_utgst = (inv_utgst * tax_multiplier).quantize(Decimal("0.0001"))
        final_cess = (inv_cess * tax_multiplier).quantize(Decimal("0.0001"))
        
        raw_total = adjusted_subtotal + final_cgst + final_sgst + final_igst + final_utgst + final_cess + header_shipping
        rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
        round_off = rounded_total - raw_total

        invoice.subtotal = inv_subtotal
        invoice.discount_total = discount_amount
        invoice.cgst_amount = final_cgst
        invoice.sgst_amount = final_sgst
        invoice.igst_amount = final_igst
        invoice.utgst_amount = final_utgst
        invoice.cess_amount = final_cess
        invoice.round_off = round_off
        invoice.shipping_charges = header_shipping
        invoice.total = rounded_total
        invoice.lines = db_lines

    db.commit()
    db.refresh(invoice)
    return invoice

@router.post("/{id}/finalize", response_model=InvoiceResponse)
def finalize_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    if invoice.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft invoices can be finalized.")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if invoice.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_invoice_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        invoice_date=invoice.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
        cgst_account_id=cgst_account_id,
        cgst_amount=invoice.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=invoice.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=invoice.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=invoice.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=invoice.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=invoice.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    invoice.status = "POSTED"
    db.commit()
    db.refresh(invoice)
    return invoice

@router.post("/{id}/payment", response_model=InvoiceResponse)
def record_invoice_payment(
    id: uuid.UUID,
    payload: PaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    if invoice.status in ("DRAFT", "CANCELLED", "PAID"):
        raise HTTPException(status_code=400, detail="Cannot record payments on draft, cancelled, or fully paid invoices.")

    payment = Payment(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        payment_number=payload.payment_number,
        payment_date=payload.payment_date,
        payment_mode=payload.payment_mode,
        amount=payload.amount,
        reference_number=payload.reference_number,
        description=payload.description
    )

    db.add(payment)
    db.flush()

    allocated_amount = Decimal("0.0000")
    for alloc in payload.allocations:
        if alloc.invoice_id != id:
            raise HTTPException(status_code=400, detail="Allocation invoice ID mismatch.")

        remaining = invoice.total - invoice.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(status_code=400, detail=f"Allocation amount {alloc.amount} exceeds invoice remaining total {remaining}")

        db_alloc = PaymentAllocation(
            payment_id=payment.id,
            invoice_id=invoice.id,
            amount=alloc.amount
        )
        db.add(db_alloc)
        allocated_amount += alloc.amount

    if payload.amount != allocated_amount:
        raise HTTPException(
            status_code=400,
            detail=f"Payment amount ({payload.amount}) must equal total allocated amount ({allocated_amount})."
        )

    invoice.amount_paid += allocated_amount
    if invoice.amount_paid >= invoice.total:
        invoice.status = "PAID"
    else:
        invoice.status = "PARTIALLY_PAID"

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{payload.payment_mode.lower()}")
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")

    ledger_draft = LedgerPostingEngine.create_payment_receipt_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        payment_date=payment.payment_date,
        bank_or_cash_account_id=bank_or_cash_account_id,
        customer_account_id=customer_account_id,
        amount=payload.amount
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    db.commit()
    db.refresh(invoice)
    return invoice

@router.post("/{id}/cancel", response_model=InvoiceResponse)
def cancel_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    
    if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
        raise HTTPException(status_code=400, detail="Only posted or partially paid invoices can be cancelled.")

    allocations = db.query(PaymentAllocation).filter(PaymentAllocation.invoice_id == id).all()
    if allocations:
        raise HTTPException(
            status_code=400,
            detail="Cannot cancel an invoice with applied payments. Reverse payments first."
        )

    invoice.amount_paid = Decimal("0.0000")

    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    round_off_account_id = resolver.resolve("round_off") if invoice.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_invoice_reversal_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        discount_total=invoice.discount_total,
        cgst_account_id=cgst_account_id,
        cgst_amount=invoice.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=invoice.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=invoice.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=invoice.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=invoice.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=invoice.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    invoice.status = "CANCELLED"
    db.commit()
    db.refresh(invoice)
    return invoice

@router.get("/{id}/pdf-payload")
def get_invoice_pdf_payload(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")

    settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    company = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    bank = db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_primary == True,
        BankingProfile.is_active == True
    ).first()
    contact = invoice.contact

    return {
        "company": {
            "legal_name": company.legal_name if company else None,
            "trade_name": company.trade_name if company else None,
            "gstin": company.gstin if company else None,
            "pan": company.pan if company else None,
            "logo_url": settings.logo_url if settings else None
        },
        "bank_details": {
            "bank_name": bank.bank_name if bank else None,
            "account_number": bank.account_number if bank else None,
            "ifsc_code": bank.ifsc_code if bank else None,
            "account_holder_name": bank.account_holder_name if bank else None,
            "upi_id": bank.upi_id if bank else None
        },
        "customer": {
            "name": contact.name if contact else None,
            "gstin": contact.gstin if contact else None,
            "pan": contact.pan if contact else None,
            "billing_address": contact.billing_address if contact else None,
            "state_code": contact.state_code if contact else None
        },
        "invoice": {
            "id": str(invoice.id),
            "invoice_number": invoice.invoice_number,
            "issue_date": invoice.issue_date.isoformat(),
            "due_date": invoice.due_date.isoformat(),
            "pos_state_code": invoice.pos_state_code,
            "status": invoice.status,
            "subtotal": str(invoice.subtotal.quantize(Decimal("0.01"))),
            "discount_total": str(invoice.discount_total.quantize(Decimal("0.01"))),
            "cgst_amount": str(invoice.cgst_amount.quantize(Decimal("0.01"))),
            "sgst_amount": str(invoice.sgst_amount.quantize(Decimal("0.01"))),
            "igst_amount": str(invoice.igst_amount.quantize(Decimal("0.01"))),
            "utgst_amount": str(invoice.utgst_amount.quantize(Decimal("0.01"))),
            "cess_amount": str(invoice.cess_amount.quantize(Decimal("0.01"))),
            "round_off": str(invoice.round_off.quantize(Decimal("0.01"))),
            "total": str(invoice.total.quantize(Decimal("0.01"))),
            "amount_paid": str(invoice.amount_paid.quantize(Decimal("0.01")))
        },
        "lines": [
            {
                "product_name": line.product.name if line.product else "N/A",
                "hsn_sac": line.hsn_sac,
                "quantity": float(line.quantity),
                "rate": float(line.rate),
                "discount": float(line.discount),
                "subtotal": str(line.subtotal.quantize(Decimal("0.01"))),
                "gst_rate": str(line.gst_rate.quantize(Decimal("0.01"))),
                "cgst_amount": str(line.cgst_amount.quantize(Decimal("0.01"))),
                "sgst_amount": str(line.sgst_amount.quantize(Decimal("0.01"))),
                "igst_amount": str(line.igst_amount.quantize(Decimal("0.01"))),
                "total": str(line.total.quantize(Decimal("0.01")))
            }
            for line in invoice.lines
        ]
    }


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete"))
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    
    if invoice.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft invoices can be deleted."
        )
    
    invoice.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return


@router.get("/{id}/print")
def print_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Generates a PDF for the invoice."""
    from fastapi.responses import StreamingResponse
    from src.domains.printing.invoice_pdf import generate_invoice_pdf
    from io import BytesIO

    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")

    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    template = "professional"
    if setting and setting.extra_settings:
        template = setting.extra_settings.get("pdf_template", "professional")

    items = []
    for line in invoice.lines:
        product = line.product
        items.append({
            'description': product.name if product else line.hsn_sac,
            'quantity': float(line.quantity),
            'rate': float(line.rate),
            'total': float(line.total),
        })

    pdf_bytes = generate_invoice_pdf(
        invoice_number=invoice.invoice_number,
        issue_date=invoice.issue_date,
        due_date=invoice.due_date,
        customer_name=invoice.contact.name if invoice.contact else "N/A",
        customer_gstin=invoice.contact.gstin if invoice.contact else None,
        items=items,
        subtotal=invoice.subtotal,
        cgst=invoice.cgst_amount,
        sgst=invoice.sgst_amount,
        igst=invoice.igst_amount,
        round_off=invoice.round_off,
        total=invoice.total,
        template=template,
        doc_type="INVOICE",
    )

    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=Invoice_{invoice.invoice_number}.pdf"}
    )


@router.get("/credit-notes/{id}/print")
def print_credit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    from fastapi.responses import StreamingResponse
    from src.domains.printing.invoice_pdf import generate_invoice_pdf
    from io import BytesIO

    cn = db.query(CreditNote).filter(
        CreditNote.id == id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")

    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    template = "professional"
    if setting and setting.extra_settings:
        template = setting.extra_settings.get("pdf_template", "professional")

    items = []
    for line in cn.lines:
        product = line.product
        items.append({
            'description': product.name if product else line.hsn_sac,
            'quantity': float(line.quantity),
            'rate': float(line.rate),
            'total': float(line.total),
        })

    pdf_bytes = generate_invoice_pdf(
        invoice_number=cn.credit_note_number,
        issue_date=cn.issue_date,
        due_date=cn.issue_date,
        customer_name=cn.invoice.contact.name if (cn.invoice and cn.invoice.contact) else "N/A",
        customer_gstin=cn.invoice.contact.gstin if (cn.invoice and cn.invoice.contact) else None,
        items=items,
        subtotal=cn.subtotal,
        cgst=cn.cgst_amount,
        sgst=cn.sgst_amount,
        igst=cn.igst_amount,
        round_off=cn.round_off,
        total=cn.total,
        template=template,
        doc_type="CREDIT NOTE",
    )

    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=CreditNote_{cn.credit_note_number}.pdf"}
    )


@router.get("/debit-notes/{id}/print")
def print_debit_note(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    from fastapi.responses import StreamingResponse
    from src.domains.printing.invoice_pdf import generate_invoice_pdf
    from io import BytesIO

    dn = db.query(DebitNote).filter(
        DebitNote.id == id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not dn:
        raise HTTPException(status_code=404, detail="Debit Note not found.")

    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    template = "professional"
    if setting and setting.extra_settings:
        template = setting.extra_settings.get("pdf_template", "professional")

    items = []
    for line in dn.lines:
        product = line.product
        items.append({
            'description': product.name if product else line.hsn_sac,
            'quantity': float(line.quantity),
            'rate': float(line.rate),
            'total': float(line.total),
        })

    pdf_bytes = generate_invoice_pdf(
        invoice_number=dn.debit_note_number,
        issue_date=dn.issue_date,
        due_date=dn.issue_date,
        customer_name=dn.invoice.contact.name if (dn.invoice and dn.invoice.contact) else "N/A",
        customer_gstin=dn.invoice.contact.gstin if (dn.invoice and dn.invoice.contact) else None,
        items=items,
        subtotal=dn.subtotal,
        cgst=dn.cgst_amount,
        sgst=dn.sgst_amount,
        igst=dn.igst_amount,
        round_off=dn.round_off,
        total=dn.total,
        template=template,
        doc_type="DEBIT NOTE",
    )

    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=DebitNote_{dn.debit_note_number}.pdf"}
    )


@router.delete("/credit-notes/{cn_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete"))
):
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")
    
    if cn.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft Credit Notes can be deleted."
        )
    
    cn.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return


@router.delete("/debit-notes/{dn_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_debit_note(
    dn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete"))
):
    dn = db.query(DebitNote).filter(
        DebitNote.id == dn_id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not dn:
        raise HTTPException(status_code=404, detail="Debit Note not found.")
    
    if dn.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft Debit Notes can be deleted."
        )
    
    dn.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return


@router.post("/{id}/e-invoice", response_model=EInvoiceResponse)
def generate_e_invoice_route(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    from src.domains.taxation.einvoice_service import EInvoiceService
    return EInvoiceService.generate_einvoice(db=db, tenant_id=tenant_id, invoice_id=id)


@router.post("/{id}/e-invoice/cancel", response_model=EInvoiceCancelResponse)
def cancel_e_invoice_route(
    id: uuid.UUID,
    payload: EInvoiceCancelRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    from src.domains.taxation.einvoice_service import EInvoiceService
    return EInvoiceService.cancel_einvoice(
        db=db,
        tenant_id=tenant_id,
        invoice_id=id,
        cancel_reason=payload.cancel_reason,
        cancel_remarks=payload.cancel_remarks
    )
