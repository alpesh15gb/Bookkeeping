from fastapi import APIRouter, Depends, HTTPException, status
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
    PaymentCreate, PaymentResponse, PaymentListResponse,
    BillPaymentCreate, BillPaymentResponse, BillPaymentListResponse
)
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.company.services import NumberingSeriesService
from src.api.deps import enforce_permission

router = APIRouter(prefix="/payments", tags=["Payments and Receipts"])

VALID_PAYMENT_MODES = {"cash", "bank", "upi", "pos", "other"}

@router.post("/receipts", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
def create_payment_receipt(
    payload: PaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")
    if contact.contact_type not in ("CUSTOMER", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Customer.")

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

    if not payload.allocations:
        raise HTTPException(status_code=400, detail="At least one allocation is required.")
    
    total_allocated = Decimal("0.0000")
    for alloc in payload.allocations:
        if alloc.amount <= 0:
            raise HTTPException(status_code=400, detail="Allocation amount must be greater than zero.")
        total_allocated += alloc.amount
    
    if total_allocated != payload.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sum of allocations ({total_allocated}) must equal payment amount ({payload.amount})."
        )

    invoice_ids = [alloc.invoice_id for alloc in payload.allocations]
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
        if invoice.status not in ("POSTED", "PARTIALLY_PAID"):
            raise HTTPException(status_code=400, detail=f"Invoice {invoice.invoice_number} is not in a payable state (must be POSTED or PARTIALLY_PAID).")

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

    payment = Payment(
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
    bank_or_cash_account_id = resolver.resolve(f"assets.{payload.payment_mode.lower()}")
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

    results = q.offset(offset).limit(limit).all()

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
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:cancel"))
):
    payment = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id,
        Payment.deleted_at == None
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment receipt not found.")

    if payment.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Payment receipt is already cancelled.")

    for alloc in payment.allocations:
        invoice = db.query(Invoice).filter(Invoice.id == alloc.invoice_id).with_for_update().first()
        if invoice:
            invoice.amount_paid -= alloc.amount
            if invoice.amount_paid <= 0:
                invoice.amount_paid = Decimal("0.0000")
                invoice.status = "POSTED"
            else:
                invoice.status = "PARTIALLY_PAID"

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{payment.payment_mode.lower()}")
    # Resolve customer from the first allocation's invoice
    if payment.allocations:
        first_invoice = db.query(Invoice).filter(Invoice.id == payment.allocations[0].invoice_id).first()
        customer_account_id = resolver.resolve(f"customer.{first_invoice.contact_id}") if first_invoice else None
    else:
        customer_account_id = None

    if customer_account_id:
        ledger_draft = LedgerPostingEngine.create_payment_receipt_reversal_posting(
            tenant_id=tenant_id,
            payment_id=payment.id,
            payment_number=payment.payment_number,
            cancel_date=date.today(),
            bank_or_cash_account_id=bank_or_cash_account_id,
            customer_account_id=customer_account_id,
            amount=payment.amount
        )
        commit_ledger_draft(db, tenant_id, ledger_draft)

    payment.status = "CANCELLED"
    payment.deleted_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(payment)
    return payment


@router.post("/disbursements", response_model=BillPaymentResponse, status_code=status.HTTP_201_CREATED)
def create_vendor_payment(
    payload: BillPaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
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

    for alloc in payload.allocations:
        bill = db.query(Bill).filter(
            Bill.id == alloc.bill_id,
            Bill.tenant_id == tenant_id,
            Bill.deleted_at == None
        ).with_for_update().first()
        if not bill:
            raise HTTPException(status_code=404, detail=f"Vendor Bill with ID {alloc.bill_id} not found.")
        if bill.status not in ("POSTED", "PARTIALLY_PAID"):
            raise HTTPException(status_code=400, detail=f"Bill {bill.bill_number} is not in a payable state (must be POSTED or PARTIALLY_PAID).")

        remaining = bill.total - bill.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Allocation amount {alloc.amount} exceeds remaining total {remaining} for bill {bill.bill_number}."
            )

        bill.amount_paid += alloc.amount
        if bill.amount_paid >= bill.total:
            bill.status = "PAID"
        else:
            bill.status = "PARTIALLY_PAID"

        db_alloc = BillPaymentAllocation(
            bill_id=bill.id,
            amount=alloc.amount
        )
        db_allocations.append(db_alloc)
        total_allocated += alloc.amount

    if total_allocated != payload.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sum of allocations ({total_allocated}) must equal payment amount ({payload.amount})."
        )

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
    bank_or_cash_account_id = resolver.resolve(f"assets.{payload.payment_mode.lower()}")
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
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:cancel"))
):
    payment = db.query(BillPayment).filter(
        BillPayment.id == id,
        BillPayment.tenant_id == tenant_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Disbursement not found.")

    if payment.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Disbursement is already cancelled.")

    for alloc in payment.allocations:
        bill = db.query(Bill).filter(Bill.id == alloc.bill_id).with_for_update().first()
        if bill:
            bill.amount_paid -= alloc.amount
            if bill.amount_paid <= 0:
                bill.amount_paid = Decimal("0.0000")
                bill.status = "POSTED"
            else:
                bill.status = "PARTIALLY_PAID"

    resolver = AccountResolver(db, tenant_id)
    bank_or_cash_account_id = resolver.resolve(f"assets.{payment.payment_mode.lower()}")
    vendor_account_id = resolver.resolve(f"vendor.{payment.contact_id}")

    ledger_draft = LedgerPostingEngine.create_payment_out_reversal_posting(
        tenant_id=tenant_id,
        payment_id=payment.id,
        payment_number=payment.payment_number,
        cancel_date=date.today(),
        bank_or_cash_account_id=bank_or_cash_account_id,
        vendor_account_id=vendor_account_id,
        amount=payment.amount
    )

    commit_ledger_draft(db, tenant_id, ledger_draft)

    payment.status = "CANCELLED"
    payment.deleted_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(payment)
    return payment
