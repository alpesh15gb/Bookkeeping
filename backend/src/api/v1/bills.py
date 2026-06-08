from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date, datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import Bill, BillLine, Contact, Product, BillPayment, BillPaymentAllocation, Account, JournalEntry, JournalLine, TenantSetting, BankingProfile, Tenant, User
from src.schemas.bill_schemas import BillCreate, BillUpdate, BillResponse, BillListResponse, BillPaymentCreate, PaginatedBillResponse
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.accounting.auto_post import auto_post_bill, cancel_bill, get_bill_display_status
from src.domains.company.services import resolve_origin_state_code, NumberingSeriesService
from src.api.deps import get_tenant_context, enforce_permission, get_current_user
from src.core.rate_limiter import limiter
from src.core.config import settings

router = APIRouter(prefix="/bills", tags=["Vendor Bills (Purchases)"])

@router.post("", response_model=BillResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_bill(
    request: Request,
    payload: BillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.issue_date)

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Vendor not found in this company context.")
    
    if contact.contact_type not in ("VENDOR", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Vendor.")

    origin_state_code = contact.state_code or resolve_origin_state_code(db, tenant_id)

    db_lines = []
    bill_subtotal = Decimal("0.0000")
    bill_cgst = Decimal("0.0000")
    bill_sgst = Decimal("0.0000")
    bill_igst = Decimal("0.0000")
    bill_utgst = Decimal("0.0000")
    bill_cess = Decimal("0.0000")
    bill_discount = Decimal("0.0000")

    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

        line_desc = line.description or product.name or "Item"
        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        line_subtotal = (line.quantity * line.rate) - line.discount

        # If GST-inclusive, extract the base taxable amount
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

        db_line = BillLine(
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

        bill_subtotal += db_line.subtotal
        bill_cgst += db_line.cgst_amount
        bill_sgst += db_line.sgst_amount
        bill_igst += db_line.igst_amount
        bill_utgst += db_line.utgst_amount
        bill_cess += db_line.cess_amount
        bill_discount += db_line.discount

    # Apply header-level discount and shipping
    header_discount_rate = payload.discount_rate or Decimal("0.00")
    header_shipping = payload.shipping_charges or Decimal("0.0000")

    header_discount_amt = (bill_subtotal * header_discount_rate / Decimal("100")).quantize(Decimal("0.0001"))
    adjusted_subtotal = bill_subtotal - header_discount_amt
    total_discount = bill_discount + header_discount_amt

    # Proportional tax recalculation (matching invoice pattern)
    tax_multiplier = Decimal("1.00") if bill_subtotal == 0 else adjusted_subtotal / bill_subtotal
    final_cgst = (bill_cgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_sgst = (bill_sgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_igst = (bill_igst * tax_multiplier).quantize(Decimal("0.0001"))
    final_utgst = (bill_utgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_cess = (bill_cess * tax_multiplier).quantize(Decimal("0.0001"))

    raw_total = adjusted_subtotal + final_cgst + final_sgst + final_igst + final_utgst + final_cess + header_shipping
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    # TDS calculation
    tds_rate = payload.tds_rate or Decimal("0.00")
    tds_amount = (adjusted_subtotal * tds_rate / Decimal("100")).quantize(Decimal("0.0001"))

    bill_number = payload.bill_number
    if not bill_number:
        bill_number = NumberingSeriesService.generate_next_number(db, tenant_id, "BILL")

    bill = Bill(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        bill_number=bill_number,
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=bill_subtotal,
        discount_total=total_discount,
        cgst_amount=final_cgst,
        sgst_amount=final_sgst,
        igst_amount=final_igst,
        utgst_amount=final_utgst,
        cess_amount=final_cess,
        round_off=round_off,
        total=rounded_total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        notes=payload.notes,
        terms_and_conditions=payload.terms_and_conditions,
        reference_number=payload.reference_number,
        tds_rate=tds_rate,
        tds_amount=tds_amount,
        is_gst_inclusive=payload.is_gst_inclusive if payload.is_gst_inclusive else False,
        lines=db_lines
    )

    db.add(bill)
    db.flush()

    # Bill stays as DRAFT — use /finalize endpoint to post to ledger

    db.commit()
    db.refresh(bill)
    return bill

@router.post("/preview", response_model=BillResponse, tags=["Vendor Bills (Purchases)"])
def preview_bill(
    payload: BillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first() if payload.contact_id else None

    origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)

    db_lines = []
    bill_subtotal = Decimal("0.0000")
    bill_cgst = Decimal("0.0000")
    bill_sgst = Decimal("0.0000")
    bill_igst = Decimal("0.0000")
    bill_utgst = Decimal("0.0000")
    bill_cess = Decimal("0.0000")
    bill_discount = Decimal("0.0000")

    for line in payload.line_items:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found.")

        line_desc = line.description or product.name or "Item"
        line_subtotal = (line.quantity * line.rate) - line.discount
        if line_subtotal < 0:
            raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=payload.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        )

        db_line = BillLine(
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

        bill_subtotal += db_line.subtotal
        bill_cgst += db_line.cgst_amount
        bill_sgst += db_line.sgst_amount
        bill_igst += db_line.igst_amount
        bill_utgst += db_line.utgst_amount
        bill_cess += db_line.cess_amount
        bill_discount += db_line.discount

    header_discount_rate = payload.discount_rate or Decimal("0.00")
    header_shipping = payload.shipping_charges or Decimal("0.0000")
    header_discount_amt = (bill_subtotal * header_discount_rate / Decimal("100")).quantize(Decimal("0.0001"))
    adjusted_subtotal = bill_subtotal - header_discount_amt
    total_discount = bill_discount + header_discount_amt
    tax_multiplier = Decimal("1.00") if bill_subtotal == 0 else adjusted_subtotal / bill_subtotal
    final_cgst = (bill_cgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_sgst = (bill_sgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_igst = (bill_igst * tax_multiplier).quantize(Decimal("0.0001"))
    final_utgst = (bill_utgst * tax_multiplier).quantize(Decimal("0.0001"))
    final_cess = (bill_cess * tax_multiplier).quantize(Decimal("0.0001"))
    raw_total = adjusted_subtotal + final_cgst + final_sgst + final_igst + final_utgst + final_cess + header_shipping
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    preview_bill = Bill(
        id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        bill_number="PREVIEW",
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=bill_subtotal,
        discount_total=total_discount,
        cgst_amount=final_cgst,
        sgst_amount=final_sgst,
        igst_amount=final_igst,
        utgst_amount=final_utgst,
        cess_amount=final_cess,
        round_off=round_off,
        total=rounded_total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        is_gst_inclusive=payload.is_gst_inclusive if payload.is_gst_inclusive else False,
        lines=db_lines,
        contact=contact,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )

    return preview_bill

@router.get("", response_model=PaginatedBillResponse)
def list_bills(
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
    q = db.query(Bill, Contact.name.label("contact_name"))\
        .options(joinedload(Bill.contact))\
        .join(Contact, Bill.contact_id == Contact.id)\
        .filter(Bill.tenant_id == tenant_id, Bill.deleted_at == None)

    if search:
        q = q.filter(
            Bill.bill_number.ilike(f"%{search}%") |
            Contact.name.ilike(f"%{search}%")
        )

    if status and status.upper() != "ALL":
        if status.upper() == "PAID":
            q = q.filter(Bill.status == "PAID")
        elif status.upper() == "CANCELLED":
            q = q.filter(Bill.status == "CANCELLED")
        elif status.upper() == "POSTED":
            q = q.filter(Bill.status.notin_(["PAID", "CANCELLED"]))
        else:
            q = q.filter(Bill.status == status.upper())

    if contact_id:
        q = q.filter(Bill.contact_id == contact_id)

    if date_from and date_to:
        try:
            parsed_from = date.fromisoformat(date_from)
            parsed_to = date.fromisoformat(date_to)
            q = q.filter(Bill.issue_date >= parsed_from, Bill.issue_date <= parsed_to)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    total = q.count()
    results = q.offset(offset).limit(limit).all()

    items = []
    for b, contact_name in results:
        items.append(BillListResponse(
            id=b.id,
            contact_id=b.contact_id,
            bill_number=b.bill_number,
            issue_date=b.issue_date,
            due_date=b.due_date,
            status=b.status,
            total=b.total,
            amount_paid=b.amount_paid,
            contact_name=contact_name,
            created_at=b.created_at
        ))
    return PaginatedBillResponse(items=items, total=total, page=page, limit=limit)

@router.post("/bulk-delete")
def bulk_delete_bills(
    payload: dict,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
):
    """Bulk delete multiple bills."""
    ids = payload.get("ids", [])
    if not ids:
        raise HTTPException(status_code=400, detail="No IDs provided.")

    deleted = 0
    for bill_id in ids:
        bill = db.query(Bill).filter(
            Bill.id == bill_id,
            Bill.tenant_id == tenant_id,
            Bill.deleted_at == None,
        ).first()
        if bill and bill.status == "DRAFT":
            bill.deleted_at = datetime.now(timezone.utc)
            deleted += 1

    db.commit()
    return {"deleted": deleted}


@router.get("/{id}", response_model=BillResponse)
def get_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found in this company context.")
    return bill

@router.get("/{id}/pdf-payload")
def get_bill_pdf_payload(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not bill:
        raise HTTPException(status_code=404, detail="Bill not found.")

    settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    company = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    bank = db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_primary == True,
        BankingProfile.is_active == True
    ).first()
    contact = bill.contact

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
        "vendor": {
            "name": contact.name if contact else None,
            "gstin": contact.gstin if contact else None,
            "pan": contact.pan if contact else None,
            "billing_address": contact.billing_address if contact else None,
            "state_code": contact.state_code if contact else None
        },
        "bill": {
            "id": str(bill.id),
            "bill_number": bill.bill_number,
            "issue_date": bill.issue_date.isoformat(),
            "due_date": bill.due_date.isoformat(),
            "pos_state_code": bill.pos_state_code,
            "status": bill.status,
            "subtotal": str(bill.subtotal.quantize(Decimal("0.01"))),
            "discount_total": str(bill.discount_total.quantize(Decimal("0.01"))),
            "cgst_amount": str(bill.cgst_amount.quantize(Decimal("0.01"))),
            "sgst_amount": str(bill.sgst_amount.quantize(Decimal("0.01"))),
            "igst_amount": str(bill.igst_amount.quantize(Decimal("0.01"))),
            "utgst_amount": str(bill.utgst_amount.quantize(Decimal("0.01"))),
            "cess_amount": str(bill.cess_amount.quantize(Decimal("0.01"))),
            "total": str(bill.total.quantize(Decimal("0.01"))),
            "amount_paid": str(bill.amount_paid.quantize(Decimal("0.01")))
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
            for line in bill.lines
        ]
    }


@router.put("/{id}", response_model=BillResponse)
def update_bill(
    id: uuid.UUID,
    payload: BillUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, bill.issue_date)
    if payload.issue_date:
        validate_period_open(db, tenant_id, payload.issue_date)

    if bill.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft bills can be modified.")

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Vendor not found in this context.")
        bill.contact_id = payload.contact_id
        
    if payload.bill_number:
        bill.bill_number = payload.bill_number
    if payload.issue_date:
        bill.issue_date = payload.issue_date
    if payload.due_date:
        bill.due_date = payload.due_date
    if payload.pos_state_code:
        bill.pos_state_code = payload.pos_state_code

    if payload.is_gst_inclusive is not None:
        bill.is_gst_inclusive = payload.is_gst_inclusive

    if payload.line_items is not None:
        contact = db.query(Contact).filter(Contact.id == bill.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)

        existing_lines = db.query(BillLine).filter(BillLine.bill_id == id).all()
        existing_by_id = {str(line.id): line for line in existing_lines if line.id}
        existing_by_key = {(line.product_id, line.hsn_sac, line.gst_rate, line.rate): line for line in existing_lines}

        kept_ids = set()
        db_lines = []
        bill_subtotal = Decimal("0.0000")
        bill_cgst = Decimal("0.0000")
        bill_sgst = Decimal("0.0000")
        bill_igst = Decimal("0.0000")
        bill_utgst = Decimal("0.0000")
        bill_cess = Decimal("0.0000")
        bill_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=bill.pos_state_code,
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
                db_line = BillLine(
                    bill_id=bill.id,
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

            bill_subtotal += db_line.subtotal
            bill_cgst += db_line.cgst_amount
            bill_sgst += db_line.sgst_amount
            bill_igst += db_line.igst_amount
            bill_utgst += db_line.utgst_amount
            bill_cess += db_line.cess_amount
            bill_discount += db_line.discount

        for existing_line in existing_lines:
            if str(existing_line.id) not in kept_ids:
                db.delete(existing_line)

        header_discount_rate = payload.discount_rate or Decimal("0.00")
        header_shipping = payload.shipping_charges or Decimal("0.0000")
        header_discount_amt = (bill_subtotal * header_discount_rate / Decimal("100")).quantize(Decimal("0.0001"))
        adjusted_subtotal = bill_subtotal - header_discount_amt
        total_discount = bill_discount + header_discount_amt
        tax_multiplier = Decimal("1.00") if bill_subtotal == 0 else adjusted_subtotal / bill_subtotal
        final_cgst = (bill_cgst * tax_multiplier).quantize(Decimal("0.0001"))
        final_sgst = (bill_sgst * tax_multiplier).quantize(Decimal("0.0001"))
        final_igst = (bill_igst * tax_multiplier).quantize(Decimal("0.0001"))
        final_utgst = (bill_utgst * tax_multiplier).quantize(Decimal("0.0001"))
        final_cess = (bill_cess * tax_multiplier).quantize(Decimal("0.0001"))
        raw_total = adjusted_subtotal + final_cgst + final_sgst + final_igst + final_utgst + final_cess + header_shipping
        rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
        round_off = rounded_total - raw_total

        bill.subtotal = bill_subtotal
        bill.discount_total = total_discount
        bill.cgst_amount = final_cgst
        bill.sgst_amount = final_sgst
        bill.igst_amount = final_igst
        bill.utgst_amount = final_utgst
        bill.cess_amount = final_cess
        bill.round_off = round_off
        bill.total = rounded_total
        bill.lines = db_lines

    db.commit()
    db.refresh(bill)
    return bill

@router.post("/{id}/finalize", response_model=BillResponse)
def finalize_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, bill.issue_date)

    if bill.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft bills can be finalized.")

    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    cgst_account_id = resolver.resolve("cgst_input")
    sgst_account_id = resolver.resolve("sgst_input")
    igst_account_id = resolver.resolve("igst_input")
    utgst_account_id = resolver.resolve("utgst_input")
    cess_account_id = resolver.resolve("cess_input")
    round_off_account_id = resolver.resolve("round_off") if bill.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_bill_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        bill_date=bill.issue_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=bill.subtotal,
        discount_total=bill.discount_total,
        cgst_account_id=cgst_account_id,
        cgst_amount=bill.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=bill.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=bill.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=bill.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=bill.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=bill.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    bill.status = "POSTED"
    db.commit()
    db.refresh(bill)
    return bill

@router.post("/{id}/payment", response_model=BillResponse)
def record_bill_payment(
    id: uuid.UUID,
    payload: BillPaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).with_for_update().first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found in this company context.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.payment_date)

    if bill.status in ("DRAFT", "CANCELLED", "PAID"):
        raise HTTPException(status_code=400, detail="Cannot record payment allocations on draft, cancelled, or settled bills.")

    payment = BillPayment(
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
        if alloc.bill_id != id:
            raise HTTPException(status_code=400, detail="Allocation Bill ID mismatch.")

        remaining = bill.total - bill.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(status_code=400, detail=f"Allocation amount {alloc.amount} exceeds bill remaining total {remaining}")

        db_alloc = BillPaymentAllocation(
            payment_id=payment.id,
            bill_id=bill.id,
            amount=alloc.amount
        )
        db.add(db_alloc)
        allocated_amount += alloc.amount

    if payload.amount != allocated_amount:
        raise HTTPException(
            status_code=400,
            detail=f"Payment amount ({payload.amount}) must equal total allocated amount ({allocated_amount})."
        )

    bill.amount_paid += allocated_amount
    if bill.amount_paid >= bill.total:
        bill.status = "PAID"
    else:
        bill.status = "PARTIALLY_PAID"

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{payload.payment_mode.lower()}")
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")

    ledger_draft = LedgerPostingEngine.create_payment_out_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        payment_date=payment.payment_date,
        bank_or_cash_account_id=bank_or_cash_account_id,
        vendor_account_id=vendor_account_id,
        amount=payload.amount
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    db.commit()
    db.refresh(bill)
    return bill


@router.post("/{id}/cancel", response_model=BillResponse)
def cancel_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize")),
    current_user: User = Depends(get_current_user)
):
    """Cancels a posted bill, reversing its ledger postings via the dedicated reversal engine."""
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).with_for_update().first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    if bill.status not in ("POSTED", "PARTIALLY_PAID"):
        raise HTTPException(status_code=400, detail="Only posted or partially paid bills can be cancelled.")

    allocations = db.query(BillPaymentAllocation).filter(BillPaymentAllocation.bill_id == id).all()
    if allocations:
        raise HTTPException(
            status_code=400,
            detail="Cannot cancel a bill with applied payments. Reverse payments first."
        )

    bill.amount_paid = Decimal("0.0000")

    resolver = AccountResolver(db, tenant_id)
    vendor_account_id = resolver.resolve(f"vendor.{bill.contact_id}")
    purchase_expense_account_id = resolver.resolve("purchases")
    cgst_account_id = resolver.resolve("cgst_input")
    sgst_account_id = resolver.resolve("sgst_input")
    igst_account_id = resolver.resolve("igst_input")
    utgst_account_id = resolver.resolve("utgst_input")
    cess_account_id = resolver.resolve("cess_input")
    round_off_account_id = resolver.resolve("round_off") if bill.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_bill_reversal_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        cancel_date=date.today(),
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=bill.subtotal,
        discount_total=bill.discount_total,
        cgst_account_id=cgst_account_id,
        cgst_amount=bill.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=bill.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=bill.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=bill.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=bill.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=bill.round_off,
    )

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    bill.status = "CANCELLED"
    bill.cancelled_at = datetime.now(timezone.utc)
    bill.cancelled_by = current_user.id
    db.commit()
    db.refresh(bill)
    return bill


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete"))
):
    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not bill:
        raise HTTPException(status_code=404, detail="Vendor Bill not found.")
    
    if bill.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft bills can be deleted."
        )
    
    bill.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return


@router.get("/{id}/print")
def print_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    from fastapi.responses import StreamingResponse
    from src.domains.printing.invoice_pdf import generate_invoice_pdf
    from io import BytesIO

    bill = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not bill:
        raise HTTPException(status_code=404, detail="Bill not found.")

    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    template = "professional"
    if setting and setting.extra_settings:
        template = setting.extra_settings.get("pdf_template", "professional")

    items = []
    for line in bill.lines:
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
        invoice_number=bill.bill_number,
        issue_date=bill.issue_date,
        due_date=bill.due_date,
        customer_name=bill.contact.name if bill.contact else "N/A",
        customer_gstin=bill.contact.gstin if bill.contact else None,
        items=items,
        subtotal=bill.subtotal,
        cgst=bill.cgst_amount,
        sgst=bill.sgst_amount,
        igst=bill.igst_amount,
        round_off=bill.round_off,
        total=bill.total,
        template=template,
        doc_type="BILL",
        tenant_id=tenant_id,
        db=db,
        amount_paid=bill.amount_paid or Decimal("0.00"),
        customer_address=bill.contact.billing_address if bill.contact else None,
    )

    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=Bill_{bill.bill_number}.pdf"}
    )


@router.post("/{id}/clone", response_model=BillResponse, status_code=status.HTTP_201_CREATED)
def clone_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """Clone an existing bill into a new DRAFT bill."""
    original = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None
    ).first()
    if not original:
        raise HTTPException(status_code=404, detail="Bill not found.")

    new_number = NumberingSeriesService.generate_next_number(db, tenant_id, "BILL")

    cloned = Bill(
        tenant_id=tenant_id,
        contact_id=original.contact_id,
        bill_number=new_number,
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
        total=original.total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=original.pos_state_code,
        notes=original.notes,
        terms_and_conditions=original.terms_and_conditions,
        reference_number=original.reference_number,
        tds_rate=original.tds_rate,
        tds_amount=original.tds_amount,
        lines=[
            BillLine(
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
    db.flush()
    auto_post_bill(db, tenant_id, cloned)
    db.commit()
    db.refresh(cloned)
    return cloned

