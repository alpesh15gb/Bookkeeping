from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import func
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    SalesReturn, SalesReturnLine, PurchaseReturn, PurchaseReturnLine,
    Contact, Product, Invoice, InvoiceLine, Bill, BillLine, User,
)
from src.schemas.document import (
    SalesReturnCreate, SalesReturnResponse, SalesReturnListResponse,
    PurchaseReturnCreate, PurchaseReturnResponse, PurchaseReturnListResponse,
)
from src.domains.taxation.filing_lock import (
    ensure_outward_period_mutable, ensure_gst_period_mutable, GSTPeriodFiledError,
)
from src.domains.accounting.auto_post import (
    auto_post_sales_return, auto_post_purchase_return,
    cancel_sales_return, cancel_purchase_return,
)
from src.domains.company.services import NumberingSeriesService
from src.api.deps import enforce_permission, get_current_user
from src.core.rate_limiter import limiter
from src.core.config import settings

router = APIRouter(prefix="/returns", tags=["Returns"])


# ─── SALES RETURNS ──────────────────────────────────────────────────────

@router.post("/sales", response_model=SalesReturnResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_sales_return(
    request: Request,
    payload: SalesReturnCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.issue_date)
    try:
        ensure_outward_period_mutable(db, tenant_id, payload.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    invoice = db.query(Invoice).filter(
        Invoice.id == payload.invoice_id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not invoice or invoice.status not in ("POSTED", "SENT", "PARTIALLY_PAID", "PAID"):
        raise HTTPException(status_code=400, detail="Sales returns require a posted, non-cancelled source invoice.")
    if invoice.contact_id != payload.contact_id:
        raise HTTPException(status_code=400, detail="Customer must match the source invoice.")
    if invoice.pos_state_code != payload.pos_state_code:
        raise HTTPException(status_code=400, detail="Place of supply must match the source invoice.")

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found.")

    return_number = NumberingSeriesService.generate_next_number(db, tenant_id, "SALES_RETURN")
    db_lines = []
    sr_subtotal = Decimal("0.0000")
    sr_cgst = Decimal("0.0000")
    sr_sgst = Decimal("0.0000")
    sr_igst = Decimal("0.0000")
    sr_utgst = Decimal("0.0000")
    sr_cess = Decimal("0.0000")

    for line in payload.line_items:
        source = db.query(InvoiceLine).filter(
            InvoiceLine.id == line.invoice_line_id,
            InvoiceLine.invoice_id == invoice.id,
        ).first()
        if not source or source.product_id != line.product_id:
            raise HTTPException(status_code=400, detail="Return line does not belong to the source invoice.")
        prior = db.query(
            func.coalesce(func.sum(SalesReturnLine.quantity), 0),
            func.coalesce(func.sum(SalesReturnLine.subtotal), 0),
            func.coalesce(func.sum(SalesReturnLine.cgst_amount), 0),
            func.coalesce(func.sum(SalesReturnLine.sgst_amount), 0),
            func.coalesce(func.sum(SalesReturnLine.igst_amount), 0),
            func.coalesce(func.sum(SalesReturnLine.utgst_amount), 0),
            func.coalesce(func.sum(SalesReturnLine.cess_amount), 0),
        ).join(SalesReturn, SalesReturnLine.sales_return_id == SalesReturn.id).filter(
            SalesReturn.tenant_id == tenant_id,
            SalesReturn.status == "POSTED",
            SalesReturnLine.invoice_line_id == source.id,
        ).one()
        remaining = source.quantity - Decimal(prior[0])
        if line.quantity > remaining:
            raise HTTPException(status_code=400, detail=f"Return quantity exceeds invoice quantity remaining ({remaining}).")
        complete = line.quantity == remaining
        ratio = line.quantity / source.quantity
        def returned(source_amount, prior_amount):
            return (source_amount - Decimal(prior_amount)) if complete else (source_amount * ratio).quantize(Decimal("0.01"))
        line_subtotal = returned(source.subtotal, prior[1])
        cgst_amount, sgst_amount = returned(source.cgst_amount, prior[2]), returned(source.sgst_amount, prior[3])
        igst_amount, utgst_amount = returned(source.igst_amount, prior[4]), returned(source.utgst_amount, prior[5])
        cess_amount = returned(source.cess_amount, prior[6])
        line_total = line_subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount

        db_line = SalesReturnLine(
            invoice_line_id=source.id,
            product_id=source.product_id,
            description=line.description or source.description,
            quantity=line.quantity,
            rate=(source.subtotal / source.quantity).quantize(Decimal("0.0001")),
            subtotal=line_subtotal,
            hsn_sac=source.hsn_sac,
            gst_rate=source.gst_rate,
            cgst_rate=source.cgst_rate, cgst_amount=cgst_amount,
            sgst_rate=source.sgst_rate, sgst_amount=sgst_amount,
            igst_rate=source.igst_rate, igst_amount=igst_amount,
            utgst_rate=source.utgst_rate, utgst_amount=utgst_amount,
            cess_rate=source.cess_rate, cess_amount=cess_amount,
            total=line_total,
        )
        db_lines.append(db_line)
        sr_subtotal += line_subtotal
        sr_cgst += cgst_amount
        sr_sgst += sgst_amount
        sr_igst += igst_amount
        sr_utgst += utgst_amount
        sr_cess += cess_amount

    raw_total = sr_subtotal + sr_cgst + sr_sgst + sr_igst + sr_utgst + sr_cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    sr = SalesReturn(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        invoice_id=invoice.id,
        return_number=return_number,
        issue_date=payload.issue_date,
        status="DRAFT",
        subtotal=sr_subtotal,
        cgst_amount=sr_cgst,
        sgst_amount=sr_sgst,
        igst_amount=sr_igst,
        utgst_amount=sr_utgst,
        cess_amount=sr_cess,
        round_off=round_off,
        total=rounded_total,
        pos_state_code=payload.pos_state_code,
        notes=payload.notes,
        lines=db_lines,
    )
    db.add(sr)
    db.flush()
    auto_post_sales_return(db, tenant_id, sr)
    db.commit()
    db.refresh(sr)
    return sr


@router.get("/sales", response_model=List[SalesReturnListResponse])
def list_sales_returns(
    page: int = 1,
    limit: int = 50,
    search: Optional[str] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    offset = (page - 1) * limit
    q = db.query(SalesReturn, Contact.name.label("contact_name")).join(
        Contact, SalesReturn.contact_id == Contact.id
    ).filter(
        SalesReturn.tenant_id == tenant_id,
        SalesReturn.deleted_at == None,
    )
    if search:
        q = q.filter(SalesReturn.return_number.ilike(f"%{search}%"))
    results = q.order_by(SalesReturn.issue_date.desc()).offset(offset).limit(limit).all()
    return [
        SalesReturnListResponse(
            id=sr.id,
            return_number=sr.return_number,
            issue_date=sr.issue_date,
            status=sr.status,
            total=sr.total,
            contact_name=name,
        )
        for sr, name in results
    ]


@router.get("/sales/{id}", response_model=SalesReturnResponse)
def get_sales_return(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    sr = db.query(SalesReturn).options(joinedload(SalesReturn.lines)).filter(
        SalesReturn.id == id,
        SalesReturn.tenant_id == tenant_id,
        SalesReturn.deleted_at == None,
    ).first()
    if not sr:
        raise HTTPException(status_code=404, detail="Sales return not found.")
    return sr


@router.post("/sales/{id}/cancel", response_model=SalesReturnResponse)
def cancel_sales_return_route(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize")),
    current_user: User = Depends(get_current_user),
):
    sr = db.query(SalesReturn).filter(
        SalesReturn.id == id,
        SalesReturn.tenant_id == tenant_id,
        SalesReturn.deleted_at == None,
    ).with_for_update().first()
    if not sr:
        raise HTTPException(status_code=404, detail="Sales return not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, sr.issue_date)
    try:
        ensure_outward_period_mutable(db, tenant_id, sr.issue_date)
        cancel_sales_return(db, tenant_id, sr, current_user.id)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    db.commit()
    db.refresh(sr)
    return sr


# ─── PURCHASE RETURNS ───────────────────────────────────────────────────

@router.post("/purchase", response_model=PurchaseReturnResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_purchase_return(
    request: Request,
    payload: PurchaseReturnCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.issue_date)
    try:
        ensure_gst_period_mutable(db, tenant_id, payload.issue_date)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    bill = db.query(Bill).filter(
        Bill.id == payload.bill_id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None,
    ).with_for_update().first()
    if not bill or bill.status not in ("POSTED", "PARTIALLY_PAID", "PAID"):
        raise HTTPException(status_code=400, detail="Purchase returns require a posted, non-cancelled source bill.")
    if bill.contact_id != payload.contact_id:
        raise HTTPException(status_code=400, detail="Vendor must match the source bill.")
    if bill.pos_state_code != payload.pos_state_code:
        raise HTTPException(status_code=400, detail="Place of supply must match the source bill.")

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Vendor not found.")

    return_number = NumberingSeriesService.generate_next_number(db, tenant_id, "PURCHASE_RETURN")
    db_lines = []
    pr_subtotal = Decimal("0.0000")
    pr_cgst = Decimal("0.0000")
    pr_sgst = Decimal("0.0000")
    pr_igst = Decimal("0.0000")
    pr_utgst = Decimal("0.0000")
    pr_cess = Decimal("0.0000")

    for line in payload.line_items:
        source = db.query(BillLine).filter(
            BillLine.id == line.bill_line_id,
            BillLine.bill_id == bill.id,
        ).first()
        if not source or source.product_id != line.product_id:
            raise HTTPException(status_code=400, detail="Return line does not belong to the source bill.")
        prior = db.query(
            func.coalesce(func.sum(PurchaseReturnLine.quantity), 0),
            func.coalesce(func.sum(PurchaseReturnLine.subtotal), 0),
            func.coalesce(func.sum(PurchaseReturnLine.cgst_amount), 0),
            func.coalesce(func.sum(PurchaseReturnLine.sgst_amount), 0),
            func.coalesce(func.sum(PurchaseReturnLine.igst_amount), 0),
            func.coalesce(func.sum(PurchaseReturnLine.utgst_amount), 0),
            func.coalesce(func.sum(PurchaseReturnLine.cess_amount), 0),
        ).join(PurchaseReturn, PurchaseReturnLine.purchase_return_id == PurchaseReturn.id).filter(
            PurchaseReturn.tenant_id == tenant_id,
            PurchaseReturn.status == "POSTED",
            PurchaseReturnLine.bill_line_id == source.id,
        ).one()
        remaining = source.quantity - Decimal(prior[0])
        if line.quantity > remaining:
            raise HTTPException(status_code=400, detail=f"Return quantity exceeds bill quantity remaining ({remaining}).")
        complete = line.quantity == remaining
        ratio = line.quantity / source.quantity
        def returned(source_amount, prior_amount):
            return (source_amount - Decimal(prior_amount)) if complete else (source_amount * ratio).quantize(Decimal("0.01"))
        line_subtotal = returned(source.subtotal, prior[1])
        cgst_amount, sgst_amount = returned(source.cgst_amount, prior[2]), returned(source.sgst_amount, prior[3])
        igst_amount, utgst_amount = returned(source.igst_amount, prior[4]), returned(source.utgst_amount, prior[5])
        cess_amount = returned(source.cess_amount, prior[6])
        line_total = line_subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount

        db_line = PurchaseReturnLine(
            bill_line_id=source.id,
            product_id=source.product_id,
            description=line.description or source.description,
            quantity=line.quantity,
            rate=(source.subtotal / source.quantity).quantize(Decimal("0.0001")),
            subtotal=line_subtotal,
            hsn_sac=source.hsn_sac,
            gst_rate=source.gst_rate,
            cgst_rate=source.cgst_rate, cgst_amount=cgst_amount,
            sgst_rate=source.sgst_rate, sgst_amount=sgst_amount,
            igst_rate=source.igst_rate, igst_amount=igst_amount,
            utgst_rate=source.utgst_rate, utgst_amount=utgst_amount,
            cess_rate=source.cess_rate, cess_amount=cess_amount,
            total=line_total,
        )
        db_lines.append(db_line)
        pr_subtotal += line_subtotal
        pr_cgst += cgst_amount
        pr_sgst += sgst_amount
        pr_igst += igst_amount
        pr_utgst += utgst_amount
        pr_cess += cess_amount

    raw_total = pr_subtotal + pr_cgst + pr_sgst + pr_igst + pr_utgst + pr_cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    pr = PurchaseReturn(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        bill_id=bill.id,
        return_number=return_number,
        issue_date=payload.issue_date,
        status="DRAFT",
        subtotal=pr_subtotal,
        cgst_amount=pr_cgst,
        sgst_amount=pr_sgst,
        igst_amount=pr_igst,
        utgst_amount=pr_utgst,
        cess_amount=pr_cess,
        round_off=round_off,
        total=rounded_total,
        pos_state_code=payload.pos_state_code,
        notes=payload.notes,
        lines=db_lines,
    )
    db.add(pr)
    db.flush()
    auto_post_purchase_return(db, tenant_id, pr)
    db.commit()
    db.refresh(pr)
    return pr


@router.get("/purchase", response_model=List[PurchaseReturnListResponse])
def list_purchase_returns(
    page: int = 1,
    limit: int = 50,
    search: Optional[str] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    offset = (page - 1) * limit
    q = db.query(PurchaseReturn, Contact.name.label("contact_name")).join(
        Contact, PurchaseReturn.contact_id == Contact.id
    ).filter(
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.deleted_at == None,
    )
    if search:
        q = q.filter(PurchaseReturn.return_number.ilike(f"%{search}%"))
    results = q.order_by(PurchaseReturn.issue_date.desc()).offset(offset).limit(limit).all()
    return [
        PurchaseReturnListResponse(
            id=pr.id,
            return_number=pr.return_number,
            issue_date=pr.issue_date,
            status=pr.status,
            total=pr.total,
            contact_name=name,
        )
        for pr, name in results
    ]


@router.get("/purchase/{id}", response_model=PurchaseReturnResponse)
def get_purchase_return(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    pr = db.query(PurchaseReturn).options(joinedload(PurchaseReturn.lines)).filter(
        PurchaseReturn.id == id,
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.deleted_at == None,
    ).first()
    if not pr:
        raise HTTPException(status_code=404, detail="Purchase return not found.")
    return pr


@router.post("/purchase/{id}/cancel", response_model=PurchaseReturnResponse)
def cancel_purchase_return_route(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize")),
    current_user: User = Depends(get_current_user),
):
    pr = db.query(PurchaseReturn).filter(
        PurchaseReturn.id == id,
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.deleted_at == None,
    ).with_for_update().first()
    if not pr:
        raise HTTPException(status_code=404, detail="Purchase return not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, pr.issue_date)
    try:
        ensure_gst_period_mutable(db, tenant_id, pr.issue_date)
        cancel_purchase_return(db, tenant_id, pr, current_user.id)
    except GSTPeriodFiledError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    db.commit()
    db.refresh(pr)
    return pr
