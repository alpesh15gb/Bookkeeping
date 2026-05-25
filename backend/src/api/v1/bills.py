from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import Bill, BillLine, Contact, Product, BillPayment, BillPaymentAllocation, Account, JournalEntry, JournalLine, TenantSetting, BankingProfile, Tenant
from src.schemas.bill_schemas import BillCreate, BillUpdate, BillResponse, BillListResponse, BillPaymentCreate
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/bills", tags=["Vendor Bills (Purchases)"])

@router.post("", response_model=BillResponse, status_code=status.HTTP_201_CREATED)
def create_bill(
    payload: BillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")) # vendor bill creation requires invoice:create or purchasing scopes
):
    # Verify Vendor belongs to active tenant
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

        db_line = BillLine(
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

        bill_subtotal += db_line.subtotal
        bill_cgst += db_line.cgst_amount
        bill_sgst += db_line.sgst_amount
        bill_igst += db_line.igst_amount
        bill_utgst += db_line.utgst_amount
        bill_cess += db_line.cess_amount
        bill_discount += db_line.discount

    grand_total = bill_subtotal + bill_cgst + bill_sgst + bill_igst + bill_utgst + bill_cess

    bill = Bill(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        bill_number=payload.bill_number,
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=bill_subtotal,
        discount_total=bill_discount,
        cgst_amount=bill_cgst,
        sgst_amount=bill_sgst,
        igst_amount=bill_igst,
        utgst_amount=bill_utgst,
        cess_amount=bill_cess,
        total=grand_total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        lines=db_lines
    )

    db.add(bill)
    db.commit()
    db.refresh(bill)
    return bill

@router.get("", response_model=List[BillListResponse])
def list_bills(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(Bill, Contact.name.label("contact_name"))\
        .join(Contact, Bill.contact_id == Contact.id)\
        .filter(Bill.tenant_id == tenant_id, Bill.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for b, contact_name in results:
        response.append(BillListResponse(
            id=b.id,
            bill_number=b.bill_number,
            issue_date=b.issue_date,
            due_date=b.due_date,
            status=b.status,
            total=b.total,
            amount_paid=b.amount_paid,
            contact_name=contact_name,
            created_at=b.created_at
        ))
    return response

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
    """Consolidated metadata for PDF print rendering of a vendor bill."""
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
            "subtotal": float(bill.subtotal),
            "discount_total": float(bill.discount_total),
            "cgst_amount": float(bill.cgst_amount),
            "sgst_amount": float(bill.sgst_amount),
            "igst_amount": float(bill.igst_amount),
            "utgst_amount": float(bill.utgst_amount),
            "cess_amount": float(bill.cess_amount),
            "total": float(bill.total),
            "amount_paid": float(bill.amount_paid)
        },
        "lines": [
            {
                "product_name": line.product.name if line.product else "N/A",
                "hsn_sac": line.hsn_sac,
                "quantity": float(line.quantity),
                "rate": float(line.rate),
                "discount": float(line.discount),
                "subtotal": float(line.subtotal),
                "gst_rate": float(line.gst_rate),
                "cgst_amount": float(line.cgst_amount),
                "sgst_amount": float(line.sgst_amount),
                "igst_amount": float(line.igst_amount),
                "total": float(line.total)
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

    if payload.line_items is not None:
        db.query(BillLine).filter(BillLine.bill_id == id).delete()

        contact = db.query(Contact).filter(Contact.id == bill.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)
        db_lines = []
        bill_subtotal = Decimal("0.0000")
        bill_cgst = Decimal("0.0000")
        bill_sgst = Decimal("0.0000")
        inv_igst = Decimal("0.0000") # wait, let's keep bill variables consistent
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
                gst_rate=line.gst_rate
            )

            db_line = BillLine(
                bill_id=bill.id,
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

            bill_subtotal += db_line.subtotal
            bill_cgst += db_line.cgst_amount
            bill_sgst += db_line.sgst_amount
            bill_igst += db_line.igst_amount
            bill_utgst += db_line.utgst_amount
            bill_cess += db_line.cess_amount
            bill_discount += db_line.discount

        bill.subtotal = bill_subtotal
        bill.discount_total = bill_discount
        bill.cgst_amount = bill_cgst
        bill.sgst_amount = bill_sgst
        bill.igst_amount = bill_igst
        bill.utgst_amount = bill_utgst
        bill.cess_amount = bill_cess
        bill.total = bill_subtotal + bill_cgst + bill_sgst + bill_igst + bill_utgst + bill_cess
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

    ledger_draft = LedgerPostingEngine.create_bill_posting(
        tenant_id=tenant_id,
        bill_id=bill.id,
        bill_number=bill.bill_number,
        bill_date=bill.issue_date,
        vendor_account_id=vendor_account_id,
        purchase_expense_account_id=purchase_expense_account_id,
        subtotal=bill.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=bill.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=bill.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=bill.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=bill.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=bill.cess_amount
    )

    journal_entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=ledger_draft.entry_date,
        reference_number=ledger_draft.reference_number,
        description=ledger_draft.description,
        source_type=ledger_draft.source_type,
        source_id=ledger_draft.source_id,
        lines=[
            JournalLine(
                account_id=line.account_id,
                amount=line.amount,
                direction=line.direction,
                narration=line.narration
            )
            for line in ledger_draft.lines
        ]
    )

    bill.status = "UNPAID"
    db.add(journal_entry)

    # Update account balances
    for line in ledger_draft.lines:
        account = db.query(Account).filter(
            Account.id == line.account_id,
            Account.tenant_id == tenant_id,
            Account.deleted_at == None
        ).with_for_update().first()
        if account:
            if account.account_type in ("ASSET", "EXPENSE"):
                if line.direction == "DEBIT":
                    account.current_balance += line.amount
                else:
                    account.current_balance -= line.amount
            else:
                if line.direction == "CREDIT":
                    account.current_balance += line.amount
                else:
                    account.current_balance -= line.amount

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

    journal_entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=ledger_draft.entry_date,
        reference_number=ledger_draft.reference_number,
        description=ledger_draft.description,
        source_type=ledger_draft.source_type,
        source_id=ledger_draft.source_id,
        lines=[
            JournalLine(
                account_id=line.account_id,
                amount=line.amount,
                direction=line.direction,
                narration=line.narration
            )
            for line in ledger_draft.lines
        ]
    )

    db.add(journal_entry)

    # Update account balances
    for line in ledger_draft.lines:
        account = db.query(Account).filter(
            Account.id == line.account_id,
            Account.tenant_id == tenant_id,
            Account.deleted_at == None
        ).with_for_update().first()
        if account:
            if account.account_type in ("ASSET", "EXPENSE"):
                if line.direction == "DEBIT":
                    account.current_balance += line.amount
                else:
                    account.current_balance -= line.amount
            else:
                if line.direction == "CREDIT":
                    account.current_balance += line.amount
                else:
                    account.current_balance -= line.amount

    db.commit()
    db.refresh(bill)
    return bill
