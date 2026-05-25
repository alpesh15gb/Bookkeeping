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
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import NumberingSeriesService
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/payments", tags=["Payments and Receipts"])

@router.post("/receipts", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
def create_payment_receipt(
    payload: PaymentCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    """Records a customer payment receipt, allocating it to one or more sales invoices."""
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")
    if contact.contact_type not in ("CUSTOMER", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Customer.")

    # Numbering series auto-generation
    payment_number = payload.payment_number
    if not payment_number:
        payment_number = NumberingSeriesService.generate_next_number(db, tenant_id, "RECEIPT")

    # Check duplicate payment number under same tenant
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

    # Validate allocations
    total_allocated = Decimal("0.0000")
    db_allocations = []

    for alloc in payload.allocations:
        invoice = db.query(Invoice).filter(
            Invoice.id == alloc.invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.deleted_at == None
        ).with_for_update().first()
        if not invoice:
            raise HTTPException(status_code=404, detail=f"Invoice with ID {alloc.invoice_id} not found.")
        if invoice.status not in ("SENT", "PARTIALLY_PAID"):
            raise HTTPException(status_code=400, detail=f"Invoice {invoice.invoice_number} is not in a payable state (must be SENT or PARTIALLY_PAID).")

        remaining = invoice.total - invoice.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Allocation amount {alloc.amount} exceeds remaining total {remaining} for invoice {invoice.invoice_number}."
            )

        # Update invoice amount_paid
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
        total_allocated += alloc.amount

    if total_allocated > payload.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sum of allocations ({total_allocated}) exceeds total payment amount ({payload.amount})."
        )

    # Create Payment record
    payment = Payment(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        payment_number=payment_number,
        payment_date=payload.payment_date,
        payment_mode=payload.payment_mode,
        amount=payload.amount,
        reference_number=payload.reference_number,
        description=payload.description,
        allocations=db_allocations
    )
    db.add(payment)
    db.flush()

    # Ledger posting
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
    """Lists customer payment receipts, optionally filtered by customer contact ID."""
    offset = (page - 1) * limit
    q = db.query(Payment, Contact.name.label("contact_name"))\
        .join(Contact, Payment.contact_id == Contact.id)\
        .filter(Payment.tenant_id == tenant_id)

    if contact_id:
        q = q.filter(Payment.contact_id == contact_id)

    results = q.offset(offset).limit(limit).all()

    response = []
    for pay, contact_name in results:
        status_str = "CANCELLED" if pay.deleted_at is not None else "ACTIVE"
        response.append(PaymentListResponse(
            id=pay.id,
            payment_number=pay.payment_number,
            payment_date=pay.payment_date,
            payment_mode=pay.payment_mode,
            amount=pay.amount,
            contact_name=contact_name,
            status=status_str,
            created_at=pay.created_at
        ))
    return response

@router.get("/receipts/{id}", response_model=PaymentResponse)
def get_payment_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view"))
):
    """Fetches details of a single customer payment receipt."""
    payment = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment receipt not found.")
    return payment

@router.post("/receipts/{id}/cancel", response_model=PaymentResponse)
def cancel_payment_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    """Cancels a customer receipt, reversing its invoice allocations and posting reversal journal entries."""
    payment = db.query(Payment).filter(
        Payment.id == id,
        Payment.tenant_id == tenant_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment receipt not found.")

    if payment.deleted_at is not None:
        raise HTTPException(status_code=400, detail="Payment receipt is already cancelled.")

    # Revert invoice allocations
    for alloc in payment.allocations:
        invoice = db.query(Invoice).filter(Invoice.id == alloc.invoice_id).first()
        if invoice:
            invoice.amount_paid -= alloc.amount
            if invoice.amount_paid <= 0:
                invoice.amount_paid = Decimal("0.0000")
                invoice.status = "SENT"
            else:
                invoice.status = "PARTIALLY_PAID"

    # Post reversal entries
    orig_entry = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == "PAYMENT",
        JournalEntry.source_id == payment.id
    ).first()

    if orig_entry:
        reversal_lines = []
        for line in orig_entry.lines:
            rev_direction = "CREDIT" if line.direction == "DEBIT" else "DEBIT"
            reversal_lines.append(
                JournalLine(
                    account_id=line.account_id,
                    amount=line.amount,
                    direction=rev_direction,
                    narration=f"Reversal: {line.narration or ''}"
                )
            )

        reversal_entry = JournalEntry(
            tenant_id=tenant_id,
            entry_date=date.today(),
            reference_number=f"REV-{payment.payment_number}",
            description=f"Reversal entry for payment receipt {payment.payment_number}",
            source_type="PAYMENT",
            source_id=payment.id,
            lines=reversal_lines
        )
        db.add(reversal_entry)

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
    """Records a vendor payment out, allocating it to one or more vendor bills."""
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Vendor not found in this company context.")
    if contact.contact_type not in ("VENDOR", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Vendor.")

    # Numbering series auto-generation
    payment_number = payload.payment_number
    if not payment_number:
        payment_number = NumberingSeriesService.generate_next_number(db, tenant_id, "DISBURSEMENT")

    # Check duplicate payment number under same tenant
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

    # Validate allocations
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
        if bill.status not in ("UNPAID", "PARTIALLY_PAID"):
            raise HTTPException(status_code=400, detail=f"Bill {bill.bill_number} is not in a payable state (must be UNPAID or PARTIALLY_PAID).")

        remaining = bill.total - bill.amount_paid
        if alloc.amount > remaining:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Allocation amount {alloc.amount} exceeds remaining total {remaining} for bill {bill.bill_number}."
            )

        # Update bill amount_paid
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

    if total_allocated > payload.amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sum of allocations ({total_allocated}) exceeds total payment amount ({payload.amount})."
        )

    # Create BillPayment record
    payment = BillPayment(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        payment_number=payment_number,
        payment_date=payload.payment_date,
        payment_mode=payload.payment_mode,
        amount=payload.amount,
        reference_number=payload.reference_number,
        description=payload.description,
        allocations=db_allocations
    )
    db.add(payment)
    db.flush()

    # Ledger posting
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
    """Lists vendor payments out, optionally filtered by vendor contact ID."""
    offset = (page - 1) * limit
    q = db.query(BillPayment, Contact.name.label("contact_name"))\
        .join(Contact, BillPayment.contact_id == Contact.id)\
        .filter(BillPayment.tenant_id == tenant_id)

    if contact_id:
        q = q.filter(BillPayment.contact_id == contact_id)

    results = q.offset(offset).limit(limit).all()

    response = []
    for pay, contact_name in results:
        status_str = "CANCELLED" if pay.deleted_at is not None else "ACTIVE"
        response.append(BillPaymentListResponse(
            id=pay.id,
            payment_number=pay.payment_number,
            payment_date=pay.payment_date,
            payment_mode=pay.payment_mode,
            amount=pay.amount,
            contact_name=contact_name,
            status=status_str,
            created_at=pay.created_at
        ))
    return response

@router.get("/disbursements/{id}", response_model=BillPaymentResponse)
def get_vendor_payment(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:view"))
):
    """Fetches details of a single vendor payment out."""
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
    tenant_id: uuid.UUID = Depends(enforce_permission("payment:create"))
):
    """Cancels a vendor payment out, reversing its bill allocations and posting reversal journal entries."""
    payment = db.query(BillPayment).filter(
        BillPayment.id == id,
        BillPayment.tenant_id == tenant_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Disbursement not found.")

    if payment.deleted_at is not None:
        raise HTTPException(status_code=400, detail="Disbursement is already cancelled.")

    # Revert bill allocations
    for alloc in payment.allocations:
        bill = db.query(Bill).filter(Bill.id == alloc.bill_id).first()
        if bill:
            bill.amount_paid -= alloc.amount
            if bill.amount_paid <= 0:
                bill.amount_paid = Decimal("0.0000")
                bill.status = "UNPAID"
            else:
                bill.status = "PARTIALLY_PAID"

    # Post reversal entries
    orig_entry = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == "PAYMENT",
        JournalEntry.source_id == payment.id
    ).first()

    if orig_entry:
        reversal_lines = []
        for line in orig_entry.lines:
            rev_direction = "CREDIT" if line.direction == "DEBIT" else "DEBIT"
            reversal_lines.append(
                JournalLine(
                    account_id=line.account_id,
                    amount=line.amount,
                    direction=rev_direction,
                    narration=f"Reversal: {line.narration or ''}"
                )
            )

        reversal_entry = JournalEntry(
            tenant_id=tenant_id,
            entry_date=date.today(),
            reference_number=f"REV-{payment.payment_number}",
            description=f"Reversal entry for vendor payment {payment.payment_number}",
            source_type="PAYMENT",
            source_id=payment.id,
            lines=reversal_lines
        )
        db.add(reversal_entry)

    payment.deleted_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(payment)
    return payment
