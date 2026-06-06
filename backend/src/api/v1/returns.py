from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    SalesReturn, SalesReturnLine, PurchaseReturn, PurchaseReturnLine,
    Contact, Product,
)
from src.schemas.document import (
    SalesReturnCreate, SalesReturnResponse, SalesReturnListResponse,
    PurchaseReturnCreate, PurchaseReturnResponse, PurchaseReturnListResponse,
)
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, commit_ledger_draft
from src.domains.accounting.auto_post import (
    auto_post_sales_return, auto_post_purchase_return,
    cancel_sales_return, cancel_purchase_return,
)
from src.domains.company.services import NumberingSeriesService, resolve_origin_state_code
from src.api.deps import enforce_permission
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

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found.")

    return_number = NumberingSeriesService.generate_next_number(db, tenant_id, "SALES_RETURN")
    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    sr_subtotal = Decimal("0.0000")
    sr_cgst = Decimal("0.0000")
    sr_sgst = Decimal("0.0000")
    sr_igst = Decimal("0.0000")
    sr_utgst = Decimal("0.0000")
    sr_cess = Decimal("0.0000")

    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product {line.product_id} not found.")

        line_subtotal = line.quantity * line.rate
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
        )

        db_line = SalesReturnLine(
            product_id=line.product_id,
            description=line.description,
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
            total=tax_split.total_amount,
        )
        db_lines.append(db_line)
        sr_subtotal += line_subtotal
        sr_cgst += tax_split.cgst_amount
        sr_sgst += tax_split.sgst_amount
        sr_igst += tax_split.igst_amount
        sr_utgst += tax_split.utgst_amount
        sr_cess += tax_split.cess_amount

    raw_total = sr_subtotal + sr_cgst + sr_sgst + sr_igst + sr_utgst + sr_cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    sr = SalesReturn(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
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
):
    sr = db.query(SalesReturn).filter(
        SalesReturn.id == id,
        SalesReturn.tenant_id == tenant_id,
        SalesReturn.deleted_at == None,
    ).first()
    if not sr:
        raise HTTPException(status_code=404, detail="Sales return not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    cancel_sales_return(db, tenant_id, sr, tenant_id)
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

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Vendor not found.")

    return_number = NumberingSeriesService.generate_next_number(db, tenant_id, "PURCHASE_RETURN")
    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    pr_subtotal = Decimal("0.0000")
    pr_cgst = Decimal("0.0000")
    pr_sgst = Decimal("0.0000")
    pr_igst = Decimal("0.0000")
    pr_utgst = Decimal("0.0000")
    pr_cess = Decimal("0.0000")

    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product {line.product_id} not found.")

        line_subtotal = line.quantity * line.rate
        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate),
        )

        db_line = PurchaseReturnLine(
            product_id=line.product_id,
            description=line.description,
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
            total=tax_split.total_amount,
        )
        db_lines.append(db_line)
        pr_subtotal += line_subtotal
        pr_cgst += tax_split.cgst_amount
        pr_sgst += tax_split.sgst_amount
        pr_igst += tax_split.igst_amount
        pr_utgst += tax_split.utgst_amount
        pr_cess += tax_split.cess_amount

    raw_total = pr_subtotal + pr_cgst + pr_sgst + pr_igst + pr_utgst + pr_cess
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    pr = PurchaseReturn(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
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
):
    pr = db.query(PurchaseReturn).filter(
        PurchaseReturn.id == id,
        PurchaseReturn.tenant_id == tenant_id,
        PurchaseReturn.deleted_at == None,
    ).first()
    if not pr:
        raise HTTPException(status_code=404, detail="Purchase return not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    cancel_purchase_return(db, tenant_id, pr, tenant_id)
    db.commit()
    db.refresh(pr)
    return pr
