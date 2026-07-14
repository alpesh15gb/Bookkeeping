from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from datetime import datetime, date, timezone
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Payment, PaymentAllocation, Invoice, Bill, BillPayment, BillPaymentAllocation,
    Contact, JournalEntry, JournalLine
)
from src.schemas.payment_schemas import (
    PaymentCreate, PaymentResponse, PaymentListResponse, PaymentCancel,
    OutstandingInvoiceResponse,
    BillPaymentCreate, BillPaymentResponse, BillPaymentListResponse
)
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.company.services import NumberingSeriesService
from src.api.deps import enforce_permission
from src.core.rate_limiter import limiter
from src.core.config import settings

router = APIRouter(prefix="/payments", tags=["Payments and Receipts"])

VALID_PAYMENT_MODES = {"cash", "bank", "upi", "pos", "cheque", "neft_rtgs", "other"}

def _asset_account_key(payment_mode: str) -> str:
    """Map bank instruments to the bank ledger without proliferating control accounts."""
    mode = payment_mode.lower()
    return "bank" if mode in {"cheque", "neft_rtgs"} else mode

@router.post("/receipts", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_payment_receipt(
    request: Request,
    payload: PaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.payment_date)

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).with_for_update().first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")
    if contact.contact_type not in ("CUSTOMER", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Customer.")
    if not contact.is_active:
        raise HTTPException(status_code=400, detail="Selected customer is inactive.")

    payment_number = payload.payment_number
    if not payment_number:
        payment_number = NumberingSeriesService.generate_next_number(db, tenant_id, "RECEIPT")

    dup = db.query(Payment).filter(
        Payment.tenant_id == tenant_id,
        Payment.payment_number == payment_number,
        Payment.deleted_at == None
    ).first()
    if dup:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Payment receipt number {payment_number} already exists."
        )

    if payload.payment_mode.lower() not in VALID_PAYMENT_MODES:
        raise HTTPException(status_code=400, detail=f"Invalid payment mode. Must be one of: {VALID_PAYMENT_MODES}")

    invoice_ids = [alloc.invoice_id for alloc in payload.allocations]
    if len(invoice_ids) != len(set(invoice_ids)):
        raise HTTPException(status_code=400, detail="An invoice can only be allocated once per receipt.")

    total_allocated = Decimal("0.0000")
    for alloc in payload.allocations:
        if alloc.amount <= 0:
            raise HTTPException(status_code=400, detail="Allocation amount must be greater than zero.")
        total_allocated += alloc.amount
    
    # Allow total_allocated <= payment.amount (excess becomes credit balance on contact)
    if total_allocated > payload.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sum of allocations ({total_allocated}) cannot exceed payment amount ({payload.amount})."
        )

    locked_invoices = db.query(Invoice).filter(
        Invoice.id.in_(invoice_ids),
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).with_for_update().all()
    
    if len(locked_invoices) != len(invoice_ids):
        raise HTTPException(status_code=404, detail="One or more invoices not found.")
    
    invoice_map = {inv.id: inv for inv in locked_invoices}
    
    db_allocations = []
    for alloc in payload.allocations:
        invoice = invoice_map[alloc.invoice_id]
        if invoice.contact_id != contact.id:
            raise HTTPException(
                status_code=400,
                detail=f"Invoice {invoice.invoice_number} belongs to a different customer."
            )
        if invoice.status not in ("POSTED", "SENT", "PARTIALLY_PAID"):
            raise HTTPException(status_code=400, detail=f"Invoice {invoice.invoice_number} is not in a receivable state.")

        remaining = invoice.total - invoice.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Allocation amount {alloc.amount} exceeds remaining total {remaining} for invoice {invoice.invoice_number}."
            )

        invoice.amount_paid += alloc.amount
        if invoice.amount_paid >= invoice.total:
            invoice.status = "PAID"
        else:
            invoice.status = "PARTIALLY_PAID"

        db_alloc = PaymentAllocation(
            invoice_id=invoice.id,
            amount=alloc.amount
        )
        db_allocations.append(db_alloc)

    # Advance payment: excess becomes credit balance on contact
    advance_amount = payload.amount - total_allocated
    if advance_amount > 0:
        if payload.advance_supply_type is None:
            raise HTTPException(
                status_code=422,
                detail="Advance receipts must identify the intended supply as GOODS or SERVICES.",
            )
        if payload.advance_supply_type == "SERVICES":
            raise HTTPException(
                status_code=422,
                detail=(
                    "Taxable service advances require GST at receipt-voucher time. "
                    "Use a tax invoice or the dedicated taxable service advance workflow; "
                    "a non-taxed customer credit is not permitted."
                ),
            )
        contact.credit_balance = (contact.credit_balance or Decimal("0.0000")) + advance_amount

    payment = Payment(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        payment_number=payment_number,
        payment_date=payload.payment_date,
        payment_mode=payload.payment_mode.upper(),
        amount=payload.amount,
        reference_number=payload.reference_number,
        description=payload.description,
        advance_supply_type=payload.advance_supply_type if advance_amount > 0 else None,
        status="ACTIVE",
        allocations=db_allocations
    )
    db.add(payment)
    db.flush()

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{_asset_account_key(payload.payment_mode)}")
    customer_account_id = resolver.resolve(f"customer.{contact.id}")

    ledger_draft = LedgerPostingEngine.create_payment_receipt_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        payment_date=payment.payment_date,
        bank_or_cash_account_id=bank_or_cash_account_id,
        customer_account_id=customer_account_id,
        amount=payload.amount
    )

    commit_ledger_draft(db, tenant_id, ledger_draft)
    db.commit()
    db.refresh(payment)
    return payment

@router.get("/receipts", response_model=List[PaymentListResponse])
def list_payment_receipts(
    contact_id: Optional[uuid.UUID] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view"))
):
    offset = (page - 1) * limit
    q = db.query(Payment, Contact.name.label("contact_name"))\
        .join(Contact, Payment.contact_id == Contact.id)\
        .filter(Payment.tenant_id == tenant_id, Payment.deleted_at == None, Contact.deleted_at == None)

    if contact_id:
        q = q.filter(Payment.contact_id == contact_id)

    results = q.order_by(Payment.payment_date.desc(), Payment.created_at.desc()).offset(offset).limit(limit).all()

    response = []
    for pay, contact_name in results:
        response.append(PaymentListResponse(
            id=pay.id,
            payment_number=pay.payment_number,
            payment_date=pay.payment_date,
            payment_mode=pay.payment_mode,
            amount=pay.amount,
            contact_name=contact_name,
            status=pay.status or "ACTIVE",
            created_at=pay.created_at
        ))
    return response

@router.get("/receipts/outstanding/{contact_id}", response_model=List[OutstandingInvoiceResponse])
def list_customer_outstanding_invoices(
    contact_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view")),
):
    contact = db.query(Contact).filter(
        Contact.id == contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
        Contact.contact_type.in_(("CUSTOMER", "BOTH")),
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")

    invoices = db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.contact_id == contact_id,
        Invoice.deleted_at == None,
        Invoice.status.in_(("POSTED", "SENT", "PARTIALLY_PAID")),
        Invoice.amount_paid < Invoice.total,
    ).order_by(Invoice.due_date.asc(), Invoice.issue_date.asc(), Invoice.invoice_number.asc()).all()
    return [OutstandingInvoiceResponse(
        id=invoice.id,
        invoice_number=invoice.invoice_number,
        issue_date=invoice.issue_date,
        due_date=invoice.due_date,
        total=invoice.total,
        amount_paid=invoice.amount_paid,
        outstanding=invoice.total - invoice.amount_paid,
        contact_id=contact.id,
        contact_name=contact.name,
        status=invoice.status,
    ) for invoice in invoices]

@router.get("/receipts/{id}", response_model=PaymentResponse)
def get_payment_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view"))
):
    payment = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id,
        Payment.deleted_at == None
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment receipt not found.")
    return payment

@router.post("/receipts/{id}/cancel", response_model=PaymentResponse)
def cancel_payment_receipt(
    id: uuid.UUID,
    payload: Optional[PaymentCancel] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:cancel"))
):
    payment = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id,
        Payment.deleted_at == None
    ).with_for_update().first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment receipt not found.")

    from src.domains.accounting.period_lock import validate_period_open
    cancellation_date = payload.cancellation_date if payload and payload.cancellation_date else date.today()
    validate_period_open(db, tenant_id, cancellation_date)

    if payment.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Payment receipt is already cancelled.")

    contact = db.query(Contact).filter(
        Contact.id == payment.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).with_for_update().first()
    if not contact:
        raise HTTPException(status_code=409, detail="The receipt customer no longer exists.")

    allocated_total = sum((alloc.amount for alloc in payment.allocations), Decimal("0.0000"))
    advance_amount = payment.amount - allocated_total
    if advance_amount > 0 and (contact.credit_balance or Decimal("0.0000")) < advance_amount:
        raise HTTPException(
            status_code=409,
            detail="This receipt's advance credit has already been consumed. Reverse its applications before cancelling."
        )

    for alloc in payment.allocations:
        invoice = db.query(Invoice).filter(
            Invoice.id == alloc.invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.contact_id == payment.contact_id,
            Invoice.deleted_at == None,
        ).with_for_update().first()
        if invoice:
            invoice.amount_paid -= alloc.amount
            if invoice.amount_paid <= 0:
                invoice.amount_paid = Decimal("0.0000")
                invoice.status = "POSTED"
            else:
                invoice.status = "PARTIALLY_PAID"

    if advance_amount > 0:
        contact.credit_balance -= advance_amount

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{_asset_account_key(payment.payment_mode)}")
    customer_account_id = resolver.resolve(f"customer.{payment.contact_id}")
    ledger_draft = LedgerPostingEngine.create_payment_receipt_reversal_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        cancel_date=cancellation_date,
        bank_or_cash_account_id=bank_or_cash_account_id,
        customer_account_id=customer_account_id,
        amount=payment.amount
    )
    commit_ledger_draft(db, tenant_id, ledger_draft)

    payment.status = "CANCELLED"
    payment.cancelled_at = datetime.combine(cancellation_date, datetime.min.time(), tzinfo=timezone.utc)
    payment.cancellation_reason = payload.reason.strip() if payload else "Cancelled without a recorded reason"
    db.commit()
    db.refresh(payment)
    return payment


@router.post("/disbursements", response_model=BillPaymentResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_vendor_payment(
    request: Request,
    payload: BillPaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, payload.payment_date)

    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Vendor not found in this company context.")
    if contact.contact_type not in ("VENDOR", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Vendor.")

    payment_number = payload.payment_number
    if not payment_number:
        payment_number = NumberingSeriesService.generate_next_number(db, tenant_id, "DISBURSEMENT")

    dup = db.query(BillPayment).filter(
        BillPayment.tenant_id == tenant_id,
        BillPayment.payment_number == payment_number,
        BillPayment.deleted_at == None
    ).first()
    if dup:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Disbursement number {payment_number} already exists."
        )

    if payload.payment_mode.lower() not in VALID_PAYMENT_MODES:
        raise HTTPException(status_code=400, detail=f"Invalid payment mode. Must be one of: {VALID_PAYMENT_MODES}")

    total_allocated = Decimal("0.0000")
    db_allocations = []

    bill_ids = [alloc.bill_id for alloc in payload.allocations]
    if len(bill_ids) != len(set(bill_ids)):
        raise HTTPException(status_code=400, detail="A bill can only be allocated once per disbursement.")

    for alloc in payload.allocations:
        bill = db.query(Bill).filter(
            Bill.id == alloc.bill_id,
            Bill.tenant_id == tenant_id,
            Bill.deleted_at == None
        ).with_for_update().first()
        if not bill:
            raise HTTPException(status_code=404, detail=f"Vendor Bill with ID {alloc.bill_id} not found.")
        if bill.contact_id != contact.id:
            raise HTTPException(status_code=400, detail=f"Bill {bill.bill_number} belongs to a different vendor.")
        if bill.status not in ("POSTED", "PARTIALLY_PAID"):
            raise HTTPException(status_code=400, detail=f"Bill {bill.bill_number} is not in a payable state (must be POSTED or PARTIALLY_PAID).")

        payable_total = bill.total - (bill.tds_amount or Decimal("0.0000"))
        remaining = payable_total - bill.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Allocation amount {alloc.amount} exceeds remaining total {remaining} for bill {bill.bill_number}."
            )

        bill.amount_paid += alloc.amount
        if bill.amount_paid >= payable_total:
            bill.status = "PAID"
        else:
            bill.status = "PARTIALLY_PAID"

        db_alloc = BillPaymentAllocation(
            bill_id=bill.id,
            amount=alloc.amount
        )
        db_allocations.append(db_alloc)
        total_allocated += alloc.amount

    # Allow total_allocated <= payment.amount (excess becomes credit balance on contact)
    if total_allocated > payload.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sum of allocations ({total_allocated}) cannot exceed payment amount ({payload.amount})."
        )

    # Advance payment: excess becomes credit balance on vendor contact
    advance_amount = payload.amount - total_allocated
    if advance_amount > 0:
        contact.credit_balance = (contact.credit_balance or Decimal("0.0000")) + advance_amount

    payment = BillPayment(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        payment_number=payment_number,
        payment_date=payload.payment_date,
        payment_mode=payload.payment_mode,
        amount=payload.amount,
        reference_number=payload.reference_number,
        description=payload.description,
        status="ACTIVE",
        allocations=db_allocations
    )
    db.add(payment)
    db.flush()

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{_asset_account_key(payload.payment_mode)}")
    vendor_account_id = resolver.resolve(f"vendor.{contact.id}")

    ledger_draft = LedgerPostingEngine.create_payment_out_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        payment_date=payment.payment_date,
        bank_or_cash_account_id=bank_or_cash_account_id,
        vendor_account_id=vendor_account_id,
        amount=payload.amount
    )

    commit_ledger_draft(db, tenant_id, ledger_draft)
    db.commit()
    db.refresh(payment)
    return payment

@router.get("/disbursements", response_model=List[BillPaymentListResponse])
def list_vendor_payments(
    contact_id: Optional[uuid.UUID] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view"))
):
    offset = (page - 1) * limit
    q = db.query(BillPayment, Contact.name.label("contact_name"))\
        .join(Contact, BillPayment.contact_id == Contact.id)\
        .filter(BillPayment.tenant_id == tenant_id, BillPayment.deleted_at == None)

    if contact_id:
        q = q.filter(BillPayment.contact_id == contact_id)

    results = q.offset(offset).limit(limit).all()

    response = []
    for pay, contact_name in results:
        response.append(BillPaymentListResponse(
            id=pay.id,
            payment_number=pay.payment_number,
            payment_date=pay.payment_date,
            payment_mode=pay.payment_mode,
            amount=pay.amount,
            contact_name=contact_name,
            status=pay.status or "ACTIVE",
            created_at=pay.created_at
        ))
    return response

@router.get("/disbursements/{id}", response_model=BillPaymentResponse)
def get_vendor_payment(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view"))
):
    payment = db.query(BillPayment).filter(
        BillPayment.id == id,
        BillPayment.tenant_id == tenant_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Disbursement not found.")
    return payment

@router.post("/disbursements/{id}/cancel", response_model=BillPaymentResponse)
def cancel_vendor_payment(
    id: uuid.UUID,
    payload: Optional[PaymentCancel] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:cancel"))
):
    payment = db.query(BillPayment).filter(
        BillPayment.id == id,
        BillPayment.tenant_id == tenant_id
    ).with_for_update().first()
    if not payment:
        raise HTTPException(status_code=404, detail="Disbursement not found.")

    from src.domains.accounting.period_lock import validate_period_open
    cancellation_date = payload.cancellation_date if payload and payload.cancellation_date else date.today()
    validate_period_open(db, tenant_id, cancellation_date)

    if payment.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Disbursement is already cancelled.")

    contact = db.query(Contact).filter(
        Contact.id == payment.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).with_for_update().first()
    if not contact:
        raise HTTPException(status_code=409, detail="The disbursement vendor no longer exists.")

    allocated_total = sum((alloc.amount for alloc in payment.allocations), Decimal("0.0000"))
    advance_amount = payment.amount - allocated_total
    if advance_amount > 0 and (contact.credit_balance or Decimal("0.0000")) < advance_amount:
        raise HTTPException(status_code=409, detail="This vendor advance has already been consumed. Reverse its applications before cancelling.")

    for alloc in payment.allocations:
        bill = db.query(Bill).filter(
            Bill.id == alloc.bill_id,
            Bill.tenant_id == tenant_id,
            Bill.contact_id == payment.contact_id,
            Bill.deleted_at == None,
        ).with_for_update().first()
        if bill:
            bill.amount_paid -= alloc.amount
            if bill.amount_paid <= 0:
                bill.amount_paid = Decimal("0.0000")
                bill.status = "POSTED"
            else:
                bill.status = "PARTIALLY_PAID"

    if advance_amount > 0:
        contact.credit_balance -= advance_amount

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{_asset_account_key(payment.payment_mode)}")
    vendor_account_id = resolver.resolve(f"vendor.{payment.contact_id}")

    ledger_draft = LedgerPostingEngine.create_payment_out_reversal_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        cancel_date=cancellation_date,
        bank_or_cash_account_id=bank_or_cash_account_id,
        vendor_account_id=vendor_account_id,
        amount=payment.amount
    )

    commit_ledger_draft(db, tenant_id, ledger_draft)

    payment.status = "CANCELLED"
    payment.cancelled_at = datetime.combine(cancellation_date, datetime.min.time(), tzinfo=timezone.utc)
    payment.cancellation_reason = payload.reason.strip() if payload else "Cancelled without a recorded reason"
    db.commit()
    db.refresh(payment)
    return payment
