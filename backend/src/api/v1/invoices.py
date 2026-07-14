from fastapi import APIRouter, Depends, HTTPException, Query, status, Request, Body
from pydantic import BaseModel
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import func
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date, datetime, timezone
import logging

logger = logging.getLogger(__name__)


from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Contact, Product, StockLedger,
    Payment, PaymentAllocation, Account, JournalEntry, JournalLine,
    CreditNote, CreditNoteLine, DebitNote, DebitNoteLine, TenantSetting, BankingProfile, Tenant, User
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
from src.domains.taxation.filing_lock import ensure_outward_period_mutable, GSTPeriodFiledError
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.accounting.auto_post import auto_post_invoice, cancel_invoice, get_display_status
from src.domains.company.services import NumberingSeriesService, resolve_origin_state_code
from src.api.deps import enforce_permission, get_current_user
from src.core.rate_limiter import limiter
from src.core.config import settings

router = APIRouter(prefix="/invoices", tags=["Invoices"])

@router.post("", response_model=InvoiceResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_invoice(
    request: Request,
    payload: InvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.issue_date)

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
    if not contact.is_active:
        raise HTTPException(status_code=400, detail="Selected customer is inactive.")

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
        if line.quantity <= 0:
            raise HTTPException(status_code=400, detail="Line item quantity must be greater than zero.")
        if line.rate < 0:
            raise HTTPException(status_code=400, detail="Line item rate cannot be negative.")

        # Check product matches tenant context
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this company context.")

        line_desc = line.description or product.name or "Item"
        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        line_subtotal = (line.quantity * line.rate) - line.discount

        # If GST-inclusive, extract the base taxable amount
        if payload.is_gst_inclusive and resolved_gst_rate > 0:
            line_subtotal = line_subtotal / (1 + resolved_gst_rate / Decimal("100"))

        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        # Supply type overrides for exports/SEZ
        supply_type = payload.supply_type or "DOMESTIC"
        if supply_type in ("EXPORT_WITHOUT_TAX", "SEZ_WITHOUT_TAX"):
            effective_gst_rate = Decimal("0.00")
        else:
            effective_gst_rate = resolved_gst_rate
        force_igst = supply_type in ("EXPORT_WITH_TAX", "EXPORT_WITHOUT_TAX", "SEZ_WITH_TAX", "SEZ_WITHOUT_TAX")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=effective_gst_rate,
            is_rcm=payload.is_rcm or False,
            force_igst=force_igst
        )

        db_line = InvoiceLine(
            product_id=line.product_id,
            description=line_desc,
            quantity=line.quantity,
            rate=line.rate,
            discount=line.discount,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
            gst_rate=resolved_gst_rate,
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

    if rounded_total < 0:
        raise HTTPException(status_code=400, detail="Invoice total must not be negative.")

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
        notes=payload.notes,
        terms_and_conditions=payload.terms_and_conditions,
        reference_number=payload.reference_number,
        sales_person_id=payload.sales_person_id,
        is_gst_inclusive=payload.is_gst_inclusive if payload.is_gst_inclusive else False,
        is_rcm=payload.is_rcm or False,
        supply_type=payload.supply_type or "DOMESTIC",
        currency=payload.currency or "INR",
        exchange_rate=payload.exchange_rate or Decimal("1.000000"),
        tds_rate=payload.tds_rate or Decimal("0.00"),
        tcs_rate=payload.tcs_rate or Decimal("0.00"),
        lines=db_lines
    )

    db.add(invoice)
    db.flush()

    # Calculate TDS/TCS amounts on the rounded total
    if invoice.tds_rate > 0:
        invoice.tds_amount = (rounded_total * invoice.tds_rate / Decimal("100")).quantize(Decimal("0.0001"))
    if invoice.tcs_rate > 0:
        invoice.tcs_amount = (rounded_total * invoice.tcs_rate / Decimal("100")).quantize(Decimal("0.0001"))

    # Generate UPI QR code if tenant has UPI ID configured
    tenant_settings = None
    try:
        tenant_settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    except Exception as e:
        logger.warning(f"Failed to fetch tenant settings for UPI/e-invoice: {e}")
    
    if tenant_settings and getattr(tenant_settings, "upi_id", None):
        try:
            import qrcode
            import base64
            from io import BytesIO
            upi_string = f"upi://pay?pa={tenant_settings.upi_id}&pn={contact.name}&am={float(rounded_total)}&cur={invoice.currency}"
            qr = qrcode.QRCode(version=1, box_size=10, border=2)
            qr.add_data(upi_string)
            qr.make(fit=True)
            img = qr.make_image(fill_color="black", back_color="white")
            buffer = BytesIO()
            img.save(buffer, format="PNG")
            invoice.qr_code = base64.b64encode(buffer.getvalue()).decode("utf-8")
        except Exception:
            pass  # QR generation is non-critical

    # Auto-post: create journal entry immediately
    try:
        auto_post_invoice(
            db,
            tenant_id,
            invoice,
            move_stock=invoice.source_document_type != "DELIVERY_CHALLAN",
        )
    except ValueError as ve:
        db.rollback()
        raise HTTPException(status_code=422, detail=str(ve))
    except Exception as e:
        db.rollback()
        logger.error(f"Auto-post failed for invoice {invoice.id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to post invoice to ledger: {str(e)}")

    # Trigger background e-invoice generation if tenant has e-invoicing enabled
    if tenant_settings and getattr(tenant_settings, "e_invoice_enabled", None):
        try:
            import logging as _logging
            from src.workers.tasks import submit_e_invoice_to_irp
            submit_e_invoice_to_irp.delay(str(invoice.id))
        except Exception as _task_err:
            import logging as _logging
            _logging.getLogger(__name__).warning(
                f"Could not enqueue e-invoice task for invoice {invoice.id}: {_task_err}"
            )

    db.commit()
    db.refresh(invoice)
    return invoice


@router.get("/stats")
def invoice_stats(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    """Returns aggregate invoice statistics for the tenant."""
    from sqlalchemy import func, case
    stats = db.query(
        func.count(Invoice.id).label("total"),
        func.count(case((Invoice.status == "DRAFT", 1))).label("draft"),
        func.count(case((Invoice.status == "POSTED", 1))).label("posted"),
        func.count(case((Invoice.status == "PARTIALLY_PAID", 1))).label("partially_paid"),
        func.count(case((Invoice.status == "PAID", 1))).label("paid"),
        func.count(case((Invoice.status == "CANCELLED", 1))).label("cancelled"),
        func.coalesce(func.sum(case((Invoice.status.in_(("POSTED", "SENT", "PARTIALLY_PAID", "PAID")), Invoice.total), else_=0)), 0).label("total_amount"),
        func.coalesce(func.sum(case((Invoice.status.in_(("POSTED", "SENT", "PARTIALLY_PAID", "PAID")), Invoice.amount_paid), else_=0)), 0).label("collected"),
    ).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).first()

    outstanding = float(round(stats.total_amount - stats.collected, 2))
    overdue = db.query(
        func.coalesce(func.sum(Invoice.total - Invoice.amount_paid), 0)
    ).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
        Invoice.status.in_(["POSTED", "SENT", "PARTIALLY_PAID"]),
        Invoice.due_date < func.current_date(),
    ).scalar() or 0

    return {
        "total": stats.total,
        "draft": stats.draft,
        "posted": stats.posted,
        "partially_paid": stats.partially_paid,
        "paid": stats.paid,
        "cancelled": stats.cancelled,
        "total_amount": float(stats.total_amount),
        "collected": float(stats.collected),
        "outstanding": float(outstanding),
        "overdue": float(overdue),
    }


@router.get("", response_model=PaginatedInvoiceResponse)
def list_invoices(
    page: int = 1,
    limit: int = 50,
    search: Optional[str] = None,
    status: Optional[str] = None,
    contact_id: Optional[uuid.UUID] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
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

    if contact_id:
        q = q.filter(Invoice.contact_id == contact_id)

    if date_from and date_to:
        try:
            parsed_from = date.fromisoformat(date_from)
            parsed_to = date.fromisoformat(date_to)
            q = q.filter(Invoice.issue_date >= parsed_from, Invoice.issue_date <= parsed_to)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    total = q.count()
    results = q.order_by(Invoice.issue_date.desc(), Invoice.created_at.desc()).offset(offset).limit(limit).all()

    items = []
    for inv, contact_name in results:
        items.append(InvoiceListResponse(
            id=inv.id,
            contact_id=inv.contact_id,
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

        line_desc = line.description or product.name or "Item"
        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        line_subtotal = (line.quantity * line.rate) - line.discount

        if payload.is_gst_inclusive and resolved_gst_rate > 0:
            line_subtotal = line_subtotal / (1 + resolved_gst_rate / Decimal("100"))

        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=resolved_gst_rate
        )

        db_line = InvoiceLine(
            id=uuid.UUID(int=0),
            product_id=line.product_id,
            description=line_desc,
            quantity=line.quantity,
            rate=line.rate,
            discount=line.discount,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
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

    tds_rate = payload.tds_rate or Decimal("0.00")
    tcs_rate = payload.tcs_rate or Decimal("0.00")
    tds_amount = Decimal("0.0000")
    tcs_amount = Decimal("0.0000")
    if tds_rate > 0:
        tds_amount = (rounded_total * tds_rate / Decimal("100")).quantize(Decimal("0.0001"))
    if tcs_rate > 0:
        tcs_amount = (rounded_total * tcs_rate / Decimal("100")).quantize(Decimal("0.0001"))

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
        shipping_charges=header_shipping,
        total=rounded_total,
        vyapar_custom_fields={},
        amount_paid=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        e_invoice_status="PENDING",
        is_gst_inclusive=payload.is_gst_inclusive if payload.is_gst_inclusive else False,
        is_rcm=payload.is_rcm or False,
        supply_type=payload.supply_type or "DOMESTIC",
        currency=payload.currency or "INR",
        exchange_rate=payload.exchange_rate or Decimal("1.000000"),
        tds_rate=tds_rate,
        tds_amount=tds_amount,
        tcs_rate=tcs_rate,
        tcs_amount=tcs_amount,
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
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.issue_date)

    if payload.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == payload.invoice_id, Invoice.tenant_id == tenant_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="Invoice not found.")
        if inv.status in ("DRAFT", "CANCELLED"):
            raise HTTPException(status_code=400, detail="Credit notes require a posted invoice.")
    elif payload.restock_items:
        raise HTTPException(status_code=400, detail="Stock-return credit notes must reference an invoice.")

    cn_number = payload.credit_note_number
    if not cn_number:
        cn_number = NumberingSeriesService.generate_next_number(db, tenant_id, "CREDIT_NOTE")

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
        if payload.invoice_id:
            invoice_quantity = sum(
                (invoice_line.quantity for invoice_line in inv.lines if invoice_line.product_id == line.product_id),
                Decimal("0"),
            )
            if invoice_quantity <= 0:
                raise HTTPException(status_code=400, detail="Credit note item was not sold on the referenced invoice.")
            if line.quantity > invoice_quantity:
                raise HTTPException(status_code=400, detail="Credit note quantity exceeds the invoiced quantity.")
        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        line_discount = line.discount if hasattr(line, 'discount') and line.discount else Decimal("0.0000")
        line_subtotal = (line.quantity * line.rate) - line_discount
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=resolved_gst_rate
        )

        db_line = CreditNoteLine(
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
            gst_rate=resolved_gst_rate,
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
        restock_items=payload.restock_items,
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
    db.flush()

    # Credit note stays as DRAFT — use /finalize endpoint to post to ledger

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
        line_discount = line.discount if hasattr(line, 'discount') and line.discount else Decimal("0.0000")
        line_subtotal = (line.quantity * line.rate) - line_discount
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        )

        db_line = CreditNoteLine(
            id=uuid.UUID(int=0),
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
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
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    q = db.query(CreditNote).options(
        joinedload(CreditNote.invoice).joinedload(Invoice.contact)
    ).filter(
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    )
    if date_from and date_to:
        try:
            parsed_from = date.fromisoformat(date_from)
            parsed_to = date.fromisoformat(date_to)
            q = q.filter(CreditNote.issue_date >= parsed_from, CreditNote.issue_date <= parsed_to)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")
    notes = q.all()
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
    ).with_for_update().first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, cn.issue_date)

    if cn.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft Credit Notes can be finalized.")

    if cn.restock_items:
        if not cn.invoice:
            raise HTTPException(status_code=400, detail="Stock-return credit notes require an invoice.")
        for line in cn.lines:
            sold_quantity = sum(
                (item.quantity for item in cn.invoice.lines if item.product_id == line.product_id),
                Decimal("0"),
            )
            already_returned = db.query(func.coalesce(func.sum(CreditNoteLine.quantity), 0)).join(
                CreditNote, CreditNote.id == CreditNoteLine.credit_note_id
            ).filter(
                CreditNote.tenant_id == tenant_id,
                CreditNote.invoice_id == cn.invoice_id,
                CreditNote.id != cn.id,
                CreditNote.status == "POSTED",
                CreditNote.restock_items == True,
                CreditNoteLine.product_id == line.product_id,
            ).scalar() or Decimal("0")
            if already_returned + line.quantity > sold_quantity:
                raise HTTPException(
                    status_code=409,
                    detail="Cumulative returned quantity exceeds the quantity sold.",
                )

    # Guard against double-posting
    from src.domains.accounting.auto_post import _check_no_existing_posting
    _check_no_existing_posting(db, tenant_id, "CREDIT_NOTE", cn.id)

    contact_id = cn.invoice.contact_id if cn.invoice else None
    if not contact_id:
        raise HTTPException(status_code=400, detail="Credit Note must be linked to a contact or invoice for finalization.")
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{contact_id}")

    # Determine the correct revenue reversal account:
    # - Same FY as original invoice → use sales_revenue (normal return)
    # - Different FY → use prior_period_adjustment (prior period correction)
    revenue_account_id = resolver.resolve("sales_revenue")
    if cn.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == cn.invoice_id, Invoice.tenant_id == tenant_id).first()
        if inv:
            from src.infrastructure.database.models import FinancialYear
            cn_fy = db.query(FinancialYear).filter(
                FinancialYear.tenant_id == tenant_id,
                FinancialYear.start_date <= cn.issue_date,
                FinancialYear.end_date >= cn.issue_date,
            ).first()
            inv_fy = db.query(FinancialYear).filter(
                FinancialYear.tenant_id == tenant_id,
                FinancialYear.start_date <= inv.issue_date,
                FinancialYear.end_date >= inv.issue_date,
            ).first()
            if cn_fy and inv_fy and cn_fy.id != inv_fy.id:
                revenue_account_id = resolver.resolve("prior_period_adjustment")

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
        sales_revenue_account_id=revenue_account_id,
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

    if cn.restock_items:
        for line in cn.lines:
            product = db.query(Product).filter(
                Product.id == line.product_id,
                Product.tenant_id == tenant_id,
                Product.deleted_at == None,
            ).with_for_update().first()
            if product and product.product_type == "GOODS":
                product.current_stock = (product.current_stock or Decimal("0")) + line.quantity
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=line.product_id,
                    reference_type="CREDIT_NOTE",
                    reference_id=cn.id,
                    quantity=line.quantity,
                    balance_quantity=product.current_stock,
                    rate=line.rate,
                ))

    # Reduce the linked invoice's outstanding by treating the CN as a credit
    if cn.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == cn.invoice_id, Invoice.tenant_id == tenant_id).first()
        if inv:
            inv.amount_paid = (inv.amount_paid or Decimal("0.0000")) + cn.total
            if inv.amount_paid >= inv.total:
                inv.status = "PAID"
            elif inv.amount_paid > 0:
                inv.status = "PARTIALLY_PAID"

    cn.status = "POSTED"
    db.commit()
    db.refresh(cn)
    return cn


@router.post("/credit-notes/{cn_id}/cancel", response_model=CreditNoteResponse)
def cancel_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize")),
    current_user: User = Depends(get_current_user),
):
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).with_for_update().first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    if cn.status != "POSTED":
        raise HTTPException(status_code=400, detail="Only posted Credit Notes can be cancelled.")
    try:
        ensure_outward_period_mutable(db, tenant_id, cn.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

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

    stock_moves = db.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "CREDIT_NOTE",
        StockLedger.reference_id == cn.id,
    ).all()
    for move in stock_moves:
        product = db.query(Product).filter(
            Product.id == move.product_id,
            Product.tenant_id == tenant_id,
        ).with_for_update().first()
        if product:
            available = product.current_stock or Decimal("0")
            if available < move.quantity:
                raise HTTPException(
                    status_code=409,
                    detail="Returned stock has already been consumed; reverse downstream stock movements first.",
                )
            product.current_stock = available - move.quantity
            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=move.product_id,
                reference_type="CREDIT_NOTE_REVERSAL",
                reference_id=cn.id,
                quantity=-move.quantity,
                balance_quantity=product.current_stock,
                rate=move.rate,
            ))

    # Reverse the outstanding impact on the linked invoice
    if cn.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == cn.invoice_id, Invoice.tenant_id == tenant_id).first()
        if inv:
            inv.amount_paid = (inv.amount_paid or Decimal("0.0000")) - cn.total
            if inv.amount_paid <= 0:
                inv.amount_paid = Decimal("0.0000")
                inv.status = "POSTED"
            elif inv.amount_paid < inv.total:
                inv.status = "PARTIALLY_PAID"

    cn.status = "CANCELLED"
    cn.cancelled_at = datetime.now(timezone.utc)
    cn.cancelled_by = current_user.id
    db.commit()
    db.refresh(cn)
    return cn


# ==========================================
# DEBIT NOTES ROUTERS â€” statuses: DRAFT â†’ POSTED â†’ CANCELLED
# ==========================================

@router.get("/debit-notes", response_model=List[DebitNoteListResponse])
def list_debit_notes(
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    q = db.query(DebitNote).options(
        joinedload(DebitNote.invoice).joinedload(Invoice.contact)
    ).filter(
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    )
    if date_from and date_to:
        try:
            parsed_from = date.fromisoformat(date_from)
            parsed_to = date.fromisoformat(date_to)
            q = q.filter(DebitNote.issue_date >= parsed_from, DebitNote.issue_date <= parsed_to)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")
    notes = q.all()
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
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.issue_date)

    if payload.invoice_id:
        inv = db.query(Invoice).filter(Invoice.id == payload.invoice_id, Invoice.tenant_id == tenant_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="Invoice not found.")

    dn_number = payload.debit_note_number
    if not dn_number:
        dn_number = NumberingSeriesService.generate_next_number(db, tenant_id, "DEBIT_NOTE")

    origin_state = resolve_origin_state_code(db, tenant_id)
    place_of_supply = inv.pos_state_code if payload.invoice_id and inv else origin_state

    # For standalone debit notes, use the contact's state as place of supply
    if not payload.invoice_id and payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if contact and contact.state_code:
            place_of_supply = contact.state_code

    db_lines = []
    subtotal = Decimal("0.0000")
    cgst = Decimal("0.0000")
    sgst = Decimal("0.0000")
    igst = Decimal("0.0000")
    utgst = Decimal("0.0000")
    cess = Decimal("0.0000")

    for line in payload.line_items:
        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        line_discount = line.discount if hasattr(line, 'discount') and line.discount else Decimal("0.0000")
        line_subtotal = (line.quantity * line.rate) - line_discount
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=resolved_gst_rate
        )

        db_line = DebitNoteLine(
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
            gst_rate=resolved_gst_rate,
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
    db.flush()

    # Debit note stays as DRAFT — use /finalize endpoint to post to ledger

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
        line_discount = line.discount if hasattr(line, 'discount') and line.discount else Decimal("0.0000")
        line_subtotal = (line.quantity * line.rate) - line_discount
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state,
            place_of_supply_state_code=place_of_supply,
            base_amount=line_subtotal,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        )

        db_line = DebitNoteLine(
            id=uuid.UUID(int=0),
            product_id=line.product_id,
            quantity=line.quantity,
            rate=line.rate,
            subtotal=line_subtotal,
            hsn_sac=line.hsn_sac,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
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

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, dn.issue_date)

    if dn.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft Debit Notes can be finalized.")

    # Guard against double-posting
    from src.domains.accounting.auto_post import _check_no_existing_posting
    _check_no_existing_posting(db, tenant_id, "DEBIT_NOTE", dn.id)

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

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

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
    dn.cancelled_at = datetime.now(timezone.utc)
    dn.cancelled_by = tenant_id
    db.commit()
    db.refresh(dn)
    return dn
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
    invoice = db.query(Invoice).options(
        joinedload(Invoice.contact),
        joinedload(Invoice.lines),
    ).filter(
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

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, invoice.issue_date)
    if payload.issue_date:
        validate_period_open(db, tenant_id, payload.issue_date)

    if invoice.status not in ("DRAFT", "POSTED"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft or posted invoices can be edited."
        )

    if invoice.status == "POSTED":
        try:
            ensure_outward_period_mutable(db, tenant_id, invoice.issue_date)
        except GSTPeriodFiledError as exc:
            raise HTTPException(status_code=409, detail=str(exc))
        existing_allocations = db.query(PaymentAllocation).filter(PaymentAllocation.invoice_id == invoice.id).first()
        if existing_allocations:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot modify a posted invoice that has payment allocations. Reverse payments first."
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

    if payload.is_gst_inclusive is not None:
        invoice.is_gst_inclusive = payload.is_gst_inclusive

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
                gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
            )

            line_desc = line.description or product.name or "Item"

            db_line = None
            if line.id and str(line.id) in existing_by_id:
                db_line = existing_by_id[str(line.id)]
            if db_line is None:
                key = (line.product_id, line.hsn_sac, line.gst_rate, line.rate)
                db_line = existing_by_key.get(key)

            if db_line is not None:
                kept_ids.add(str(db_line.id))
                db_line.description = line_desc
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
                    description=line_desc,
                    quantity=line.quantity,
                    rate=line.rate,
                    discount=line.discount,
                    subtotal=line_subtotal,
                    hsn_sac=line.hsn_sac,
                    gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
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

    # If invoice was already posted, re-post the journal entry with updated amounts
    if invoice.status == "POSTED":
        if invoice.amount_paid and invoice.amount_paid > rounded_total:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot reduce invoice total below amount already paid ({invoice.amount_paid})."
            )

        from src.domains.accounting.auto_post import _check_no_existing_posting

        # Reverse old journal entry
        old_je = db.query(JournalEntry).filter(
            JournalEntry.source_type == "INVOICE",
            JournalEntry.source_id == invoice.id,
            JournalEntry.tenant_id == tenant_id,
        ).first()
        if old_je:
            db.query(JournalLine).filter(JournalLine.entry_id == old_je.id).delete()
            db.delete(old_je)

        # Reverse old stock entries for this invoice
        old_stock_entries = db.query(StockLedger).filter(
            StockLedger.reference_type == "INVOICE",
            StockLedger.reference_id == invoice.id,
            StockLedger.tenant_id == tenant_id,
        ).all()
        for entry in old_stock_entries:
            product = db.query(Product).filter(
                Product.id == entry.product_id, Product.tenant_id == tenant_id
            ).with_for_update().first()
            if product:
                product.current_stock = (product.current_stock or Decimal("0")) - entry.quantity
            db.delete(entry)

        # Re-post with new amounts (creates new JE + stock entries)
        auto_post_invoice(
            db,
            tenant_id,
            invoice,
            move_stock=invoice.source_document_type != "DELIVERY_CHALLAN",
        )

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
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, invoice.issue_date)

    if invoice.status not in ("DRAFT", "POSTED"):
        raise HTTPException(status_code=400, detail="Only draft or posted invoices can be finalized.")

    # If already posted, return as-is (idempotent)
    if invoice.status == "POSTED":
        db.refresh(invoice)
        return invoice

    try:
        auto_post_invoice(
            db,
            tenant_id,
            invoice,
            move_stock=invoice.source_document_type != "DELIVERY_CHALLAN",
        )
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=str(exc))
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

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.payment_date)

    if invoice.status in ("DRAFT", "CANCELLED", "PAID"):
        raise HTTPException(status_code=400, detail="Cannot record payments on draft, cancelled, or fully paid invoices.")

    p_num = payload.payment_number
    if not p_num:
        p_num = NumberingSeriesService.generate_next_number(db, tenant_id, "PAYMENT")

    payment = Payment(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        payment_number=p_num,
        payment_date=payload.payment_date,
        payment_mode=payload.payment_mode,
        amount=payload.amount,
        reference_number=payload.reference_number,
        description=payload.description
    )

    db.add(payment)
    db.flush()

    allocations = payload.allocations
    if not allocations:
        from src.schemas.document import PaymentAllocationSchema
        allocations = [
            PaymentAllocationSchema(invoice_id=invoice.id, amount=payload.amount)
        ]

    allocated_amount = Decimal("0.0000")
    for alloc in allocations:
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
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:cancel")),
    current_user: User = Depends(get_current_user)
):
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    try:
        ensure_outward_period_mutable(db, tenant_id, invoice.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, invoice.issue_date)
    
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
        cancel_date=invoice.issue_date,
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

    # Restore only stock that this invoice actually moved. Invoices sourced
    # from delivery challans have no INVOICE stock rows and therefore cannot
    # incorrectly put already-delivered goods back on hand.
    stock_moves = db.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "INVOICE",
        StockLedger.reference_id == invoice.id,
    ).all()
    for move in stock_moves:
        product = db.query(Product).filter(
            Product.id == move.product_id,
            Product.tenant_id == tenant_id,
        ).with_for_update().first()
        if product:
            restore_quantity = -move.quantity
            product.current_stock = (product.current_stock or Decimal("0")) + restore_quantity
            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=move.product_id,
                reference_type="INVOICE_REVERSAL",
                reference_id=invoice.id,
                quantity=restore_quantity,
                balance_quantity=product.current_stock,
                rate=move.rate,
            ))

    invoice.status = "CANCELLED"
    invoice.cancelled_at = datetime.now(timezone.utc)
    invoice.cancelled_by = current_user.id
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
            "amount_paid": str(invoice.amount_paid.quantize(Decimal("0.01"))),
            "balance_due": str((invoice.total - (invoice.amount_paid or Decimal("0"))).quantize(Decimal("0.01")))
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
            'description': line.description or (product.name if product else 'N/A'),
            'hsn_sac': line.hsn_sac or '',
            'gst_rate': float(line.gst_rate or 0),
            'cgst_rate': float(line.cgst_rate or 0),
            'cgst_amount': float(line.cgst_amount or 0),
            'sgst_rate': float(line.sgst_rate or 0),
            'sgst_amount': float(line.sgst_amount or 0),
            'igst_rate': float(line.igst_rate or 0),
            'igst_amount': float(line.igst_amount or 0),
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
        tenant_id=tenant_id,
        db=db,
        amount_paid=invoice.amount_paid or Decimal("0.00"),
        customer_address=invoice.contact.billing_address if invoice.contact else None,
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
            'description': line.description or (product.name if product else 'N/A'),
            'hsn_sac': line.hsn_sac or '',
            'gst_rate': float(line.gst_rate or 0),
            'cgst_rate': float(line.cgst_rate or 0),
            'cgst_amount': float(line.cgst_amount or 0),
            'sgst_rate': float(line.sgst_rate or 0),
            'sgst_amount': float(line.sgst_amount or 0),
            'igst_rate': float(line.igst_rate or 0),
            'igst_amount': float(line.igst_amount or 0),
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
        tenant_id=tenant_id,
        db=db,
        customer_address=cn.invoice.contact.billing_address if (cn.invoice and cn.invoice.contact) else None,
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
            'description': line.description or (product.name if product else 'N/A'),
            'hsn_sac': line.hsn_sac or '',
            'gst_rate': float(line.gst_rate or 0),
            'cgst_rate': float(line.cgst_rate or 0),
            'cgst_amount': float(line.cgst_amount or 0),
            'sgst_rate': float(line.sgst_rate or 0),
            'sgst_amount': float(line.sgst_amount or 0),
            'igst_rate': float(line.igst_rate or 0),
            'igst_amount': float(line.igst_amount or 0),
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
        tenant_id=tenant_id,
        db=db,
        customer_address=dn.invoice.contact.billing_address if (dn.invoice and dn.invoice.contact) else None,
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


@router.post("/{id}/clone", response_model=InvoiceResponse, status_code=status.HTTP_201_CREATED)
def clone_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """Clone an existing invoice into a new DRAFT invoice."""
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    original = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not original:
        raise HTTPException(status_code=404, detail="Invoice not found.")

    new_number = NumberingSeriesService.generate_next_number(db, tenant_id, "INVOICE")

    cloned = Invoice(
        tenant_id=tenant_id,
        contact_id=original.contact_id,
        invoice_number=new_number,
        issue_date=date.today(),
        due_date=original.due_date,
        status="DRAFT",
        subtotal=original.subtotal,
        discount_total=original.discount_total,
        cgst_amount=original.cgst_amount,
        sgst_amount=original.sgst_amount,
        igst_amount=original.igst_amount,
        utgst_amount=original.utgst_amount,
        cess_amount=original.cess_amount,
        round_off=original.round_off,
        shipping_charges=original.shipping_charges,
        total=original.total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=original.pos_state_code,
        e_invoice_status="PENDING",
        notes=original.notes,
        terms_and_conditions=original.terms_and_conditions,
        reference_number=original.reference_number,
        sales_person_id=original.sales_person_id,
        lines=[
            InvoiceLine(
                product_id=line.product_id,
                description=line.description,
                quantity=line.quantity,
                rate=line.rate,
                discount=line.discount,
                subtotal=line.subtotal,
                hsn_sac=line.hsn_sac,
                gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
                cgst_rate=line.cgst_rate,
                cgst_amount=line.cgst_amount,
                sgst_rate=line.sgst_rate,
                sgst_amount=line.sgst_amount,
                igst_rate=line.igst_rate,
                igst_amount=line.igst_amount,
                utgst_rate=line.utgst_rate,
                utgst_amount=line.utgst_amount,
                cess_rate=line.cess_rate,
                cess_amount=line.cess_amount,
                total=line.total,
            )
            for line in original.lines
        ]
    )

    db.add(cloned)
    db.commit()
    db.refresh(cloned)
    return cloned


class EmailInvoiceRequest(BaseModel):
    recipient_email: Optional[str] = None

@router.post("/{id}/email")
def email_invoice(
    id: uuid.UUID,
    payload: EmailInvoiceRequest = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:email")),
):
    """Queues an invoice email to the customer. Defaults to contact email."""
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")

    recipient = payload.recipient_email if payload else None
    if not recipient:
        contact = db.query(Contact).filter(Contact.id == invoice.contact_id).first()
        recipient = contact.email if contact and contact.email else None

    if not recipient:
        raise HTTPException(status_code=400, detail="No recipient email available.")

    from src.workers.tasks import send_invoice_email
    send_invoice_email.delay(str(invoice.id), recipient)
    return {"detail": f"Invoice email queued to {recipient}."}
