from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal
from datetime import date


from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Contact, Product, Payment, PaymentAllocation, Account, JournalEntry, JournalLine,
    CreditNote, CreditNoteLine, DebitNote, DebitNoteLine, TenantSetting, BankingProfile, Tenant
)
from src.schemas.document import (
    InvoiceCreate, InvoiceUpdate, InvoiceResponse, InvoiceListResponse, PaymentCreate,
    CreditNoteCreate, CreditNoteResponse, CreditNoteListResponse,
    DebitNoteCreate, DebitNoteResponse, DebitNoteListResponse
)
from src.schemas.einvoice_schemas import EInvoiceResponse, EInvoiceCancelRequest, EInvoiceCancelResponse
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import NumberingSeriesService, resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

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

    # 3. Round-off adjustment calculations
    raw_total = inv_subtotal + inv_cgst + inv_sgst + inv_igst + inv_utgst + inv_cess
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
        discount_total=inv_discount,
        cgst_amount=inv_cgst,
        sgst_amount=inv_sgst,
        igst_amount=inv_igst,
        utgst_amount=inv_utgst,
        cess_amount=inv_cess,
        round_off=round_off,
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

@router.get("", response_model=List[InvoiceListResponse])
def list_invoices(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    # Filter query by tenant_id (RLS handles this at DB layer, but we double-check here)
    results = db.query(Invoice, Contact.name.label("contact_name"))\
        .join(Contact, Invoice.contact_id == Contact.id)\
        .filter(Invoice.tenant_id == tenant_id, Invoice.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for inv, contact_name in results:
        response.append(InvoiceListResponse(
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
    return response

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
        # Check contact matches tenant
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
        db.query(InvoiceLine).filter(InvoiceLine.invoice_id == id).delete()

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
            db_lines.append(db_line)

            inv_subtotal += db_line.subtotal
            inv_cgst += db_line.cgst_amount
            inv_sgst += db_line.sgst_amount
            inv_igst += db_line.igst_amount
            inv_utgst += db_line.utgst_amount
            inv_cess += db_line.cess_amount
            inv_discount += db_line.discount

        invoice.subtotal = inv_subtotal
        invoice.discount_total = inv_discount
        invoice.cgst_amount = inv_cgst
        invoice.sgst_amount = inv_sgst
        invoice.igst_amount = inv_igst
        invoice.utgst_amount = inv_utgst
        invoice.cess_amount = inv_cess
        invoice.total = inv_subtotal + inv_cgst + inv_sgst + inv_igst + inv_utgst + inv_cess
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

    ledger_draft = LedgerPostingEngine.create_invoice_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        invoice_date=invoice.issue_date,
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=invoice.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=invoice.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=invoice.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=invoice.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=invoice.cess_amount
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

    invoice.status = "SENT"
    db.add(journal_entry)
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
    db.refresh(invoice)
    return invoice

@router.post("/{id}/cancel", response_model=InvoiceResponse)
def cancel_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Cancels a sent invoice, reversing its ledger postings and writing balanced reversal entries.
    Also reverses any payment allocations applied to this invoice."""
    invoice = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None
    ).with_for_update().first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    
    if invoice.status != "SENT":
        raise HTTPException(status_code=400, detail="Only finalized (SENT) invoices can be cancelled.")
    
    # Reverse payment allocations: remove allocations and reset invoice amount_paid
    allocations = db.query(PaymentAllocation).filter(PaymentAllocation.invoice_id == id).all()
    for alloc in allocations:
        db.delete(alloc)
    invoice.amount_paid = Decimal("0.0000")
    
    resolver = AccountResolver(db, tenant_id)
    customer_account_id = resolver.resolve(f"customer.{invoice.contact_id}")
    sales_revenue_account_id = resolver.resolve("sales_revenue")
    cgst_account_id = resolver.resolve("cgst_output")
    sgst_account_id = resolver.resolve("sgst_output")
    igst_account_id = resolver.resolve("igst_output")
    utgst_account_id = resolver.resolve("utgst_output")
    cess_account_id = resolver.resolve("cess_output")
    
    ledger_draft = LedgerPostingEngine.create_invoice_reversal_posting(
        tenant_id=tenant_id,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        cancel_date=date.today(),
        customer_account_id=customer_account_id,
        sales_revenue_account_id=sales_revenue_account_id,
        subtotal=invoice.subtotal,
        cgst_account_id=cgst_account_id,
        cgst_amount=invoice.cgst_amount,
        sgst_account_id=sgst_account_id,
        sgst_amount=invoice.sgst_amount,
        igst_account_id=igst_account_id,
        igst_amount=invoice.igst_amount,
        utgst_account_id=utgst_account_id,
        utgst_amount=invoice.utgst_amount,
        cess_account_id=cess_account_id,
        cess_amount=invoice.cess_amount
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
    
    invoice.status = "CANCELLED"
    db.add(journal_entry)

    # Update account balances (reversal entries reverse the original postings)
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
    db.refresh(invoice)
    return invoice

@router.get("/{id}/pdf-payload")
def get_invoice_pdf_payload(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Retrieves a consolidated metadata model ready for rendering as a PDF print invoice."""
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
            "shipping_address": contact.shipping_address if contact else None,
            "state_code": contact.state_code if contact else None
        },
        "invoice": {
            "id": str(invoice.id),
            "invoice_number": invoice.invoice_number,
            "issue_date": invoice.issue_date.isoformat(),
            "due_date": invoice.due_date.isoformat(),
            "pos_state_code": invoice.pos_state_code,
            "status": invoice.status,
            "subtotal": float(invoice.subtotal),
            "discount_total": float(invoice.discount_total),
            "cgst_amount": float(invoice.cgst_amount),
            "sgst_amount": float(invoice.sgst_amount),
            "igst_amount": float(invoice.igst_amount),
            "utgst_amount": float(invoice.utgst_amount),
            "cess_amount": float(invoice.cess_amount),
            "round_off": float(invoice.round_off),
            "total": float(invoice.total),
            "amount_paid": float(invoice.amount_paid)
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
            for line in invoice.lines
        ]
    }

# ==========================================
# CREDIT NOTES ROUTERS
# ==========================================

@router.post("/credit-notes", response_model=CreditNoteResponse, status_code=status.HTTP_201_CREATED)
def create_credit_note(
    payload: CreditNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    """Creates a draft Credit Note."""
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

@router.get("/credit-notes", response_model=List[CreditNoteListResponse])
def list_credit_notes(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Lists all credit notes for the active tenant."""
    return db.query(CreditNote).filter(CreditNote.tenant_id == tenant_id, CreditNote.deleted_at == None).all()

@router.get("/credit-notes/{cn_id}", response_model=CreditNoteResponse)
def get_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Retrieves credit note details."""
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")
    return cn

@router.get("/credit-notes/{cn_id}/pdf-payload")
def get_credit_note_pdf_payload(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Consolidated metadata for PDF print rendering of a credit note."""
    cn = db.query(CreditNote).filter(
        CreditNote.id == cn_id,
        CreditNote.tenant_id == tenant_id,
        CreditNote.deleted_at == None
    ).first()
    if not cn:
        raise HTTPException(status_code=404, detail="Credit Note not found.")

    settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    company = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    bank = db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_primary == True,
        BankingProfile.is_active == True
    ).first()
    contact = cn.invoice.contact if cn.invoice else None

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
        "credit_note": {
            "id": str(cn.id),
            "credit_note_number": cn.credit_note_number,
            "issue_date": cn.issue_date.isoformat(),
            "reason": cn.reason,
            "pos_state_code": cn.pos_state_code,
            "status": cn.status,
            "subtotal": float(cn.subtotal),
            "cgst_amount": float(cn.cgst_amount),
            "sgst_amount": float(cn.sgst_amount),
            "igst_amount": float(cn.igst_amount),
            "utgst_amount": float(cn.utgst_amount),
            "cess_amount": float(cn.cess_amount),
            "round_off": float(cn.round_off),
            "total": float(cn.total)
        },
        "lines": [
            {
                "product_name": line.product.name if line.product else "N/A",
                "hsn_sac": line.hsn_sac,
                "quantity": float(line.quantity),
                "rate": float(line.rate),
                "subtotal": float(line.subtotal),
                "gst_rate": float(line.gst_rate),
                "cgst_amount": float(line.cgst_amount),
                "sgst_amount": float(line.sgst_amount),
                "igst_amount": float(line.igst_amount),
                "total": float(line.total)
            }
            for line in cn.lines
        ]
    }


@router.post("/credit-notes/{cn_id}/finalize", response_model=CreditNoteResponse)
def finalize_credit_note(
    cn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Finalizes a credit note and posts balanced double-entry adjustments to the ledger."""
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
        cess_amount=cn.cess_amount
    )

    journal_entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=ledger_draft.entry_date,
        reference_number=ledger_draft.reference_number,
        description=ledger_draft.description,
        source_type="INVOICE",
        source_id=cn.id,
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

    cn.status = "ISSUED"
    db.add(journal_entry)
    db.commit()
    db.refresh(cn)
    return cn


# ==========================================
# DEBIT NOTES ROUTERS
# ==========================================

@router.post("/debit-notes", response_model=DebitNoteResponse, status_code=status.HTTP_201_CREATED)
def create_debit_note(
    payload: DebitNoteCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    """Creates a draft Debit Note."""
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

@router.get("/debit-notes", response_model=List[DebitNoteListResponse])
def list_debit_notes(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Lists all debit notes for the active tenant."""
    return db.query(DebitNote).filter(DebitNote.tenant_id == tenant_id, DebitNote.deleted_at == None).all()

@router.get("/debit-notes/{dn_id}", response_model=DebitNoteResponse)
def get_debit_note(
    dn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Retrieves debit note details."""
    dn = db.query(DebitNote).filter(
        DebitNote.id == dn_id,
        DebitNote.tenant_id == tenant_id,
        DebitNote.deleted_at == None
    ).first()
    if not dn:
        raise HTTPException(status_code=404, detail="Debit Note not found.")
    return dn

@router.post("/debit-notes/{dn_id}/finalize", response_model=DebitNoteResponse)
def finalize_debit_note(
    dn_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Finalizes a debit note and posts balanced double-entry adjustments to the ledger."""
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
        cess_amount=dn.cess_amount
    )

    journal_entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=ledger_draft.entry_date,
        reference_number=ledger_draft.reference_number,
        description=ledger_draft.description,
        source_type="INVOICE",
        source_id=dn.id,
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

    dn.status = "ISSUED"
    db.add(journal_entry)
    db.commit()
    db.refresh(dn)
    return dn

@router.post("/{id}/e-invoice", response_model=EInvoiceResponse)
def generate_e_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Generates an Invoice Reference Number (IRN) and a signed QR code for a B2B sales invoice."""
    from src.domains.taxation.einvoice_service import EInvoiceService
    res = EInvoiceService.generate_einvoice(db=db, tenant_id=tenant_id, invoice_id=id)
    return res

@router.post("/{id}/e-invoice/cancel", response_model=EInvoiceCancelResponse)
def cancel_e_invoice(
    id: uuid.UUID,
    payload: EInvoiceCancelRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Cancels an existing generated e-invoice on the IRP within 24 hours of generation."""
    from src.domains.taxation.einvoice_service import EInvoiceService
    res = EInvoiceService.cancel_einvoice(
        db=db,
        tenant_id=tenant_id,
        invoice_id=id,
        cancel_reason=payload.cancel_reason,
        cancel_remarks=payload.cancel_remarks
    )
    return res
