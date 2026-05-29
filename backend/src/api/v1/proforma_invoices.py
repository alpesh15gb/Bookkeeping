from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal
from datetime import date, datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    ProformaInvoice, ProformaInvoiceLine, Contact, Product, JournalEntry, JournalLine, TenantSetting, BankingProfile, Tenant
)
from src.schemas.bill_schemas import (
    ProformaInvoiceCreate, ProformaInvoiceUpdate, ProformaInvoiceResponse, ProformaInvoiceListResponse
)
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/proforma-invoices", tags=["Proforma Invoices"])


@router.post("", response_model=ProformaInvoiceResponse, status_code=status.HTTP_201_CREATED)
def create_proforma_invoice(
    payload: ProformaInvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))  # Reusing invoice:create permission for now
):
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

    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    pi_subtotal = Decimal("0.0000")
    pi_cgst = Decimal("0.0000")
    pi_sgst = Decimal("0.0000")
    pi_igst = Decimal("0.0000")
    pi_utgst = Decimal("0.0000")
    pi_cess = Decimal("0.0000")
    pi_discount = Decimal("0.0000")

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

        db_line = ProformaInvoiceLine(
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

        pi_subtotal += db_line.subtotal
        pi_cgst += db_line.cgst_amount
        pi_sgst += db_line.sgst_amount
        pi_igst += db_line.igst_amount
        pi_utgst += db_line.utgst_amount
        pi_cess += db_line.cess_amount
        pi_discount += db_line.discount

    grand_total = pi_subtotal + pi_cgst + pi_sgst + pi_igst + pi_utgst + pi_cess

    pi = ProformaInvoice(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        proforma_number=payload.proforma_number,
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=pi_subtotal,
        discount_total=pi_discount,
        cgst_amount=pi_cgst,
        sgst_amount=pi_sgst,
        igst_amount=pi_igst,
        utgst_amount=pi_utgst,
        cess_amount=pi_cess,
        total=grand_total,
        pos_state_code=payload.pos_state_code,
        lines=db_lines
    )

    db.add(pi)
    db.commit()
    db.refresh(pi)
    return pi


@router.post("/preview", response_model=ProformaInvoiceResponse)
def preview_proforma_invoice(
    payload: ProformaInvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))
):
    contact = None
    if payload.contact_id:
        contact = db.query(Contact).filter(
            Contact.id == payload.contact_id,
            Contact.tenant_id == tenant_id,
            Contact.deleted_at == None
        ).first()

    origin_state_code = resolve_origin_state_code(db, tenant_id)

    db_lines = []
    pi_subtotal = Decimal("0.0000")
    pi_cgst = Decimal("0.0000")
    pi_sgst = Decimal("0.0000")
    pi_igst = Decimal("0.0000")
    pi_utgst = Decimal("0.0000")
    pi_cess = Decimal("0.0000")
    pi_discount = Decimal("0.0000")

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

        db_line = ProformaInvoiceLine(
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

        pi_subtotal += db_line.subtotal
        pi_cgst += db_line.cgst_amount
        pi_sgst += db_line.sgst_amount
        pi_igst += db_line.igst_amount
        pi_utgst += db_line.utgst_amount
        pi_cess += db_line.cess_amount
        pi_discount += db_line.discount

    grand_total = pi_subtotal + pi_cgst + pi_sgst + pi_igst + pi_utgst + pi_cess

    pi = ProformaInvoice(
        id=uuid.UUID("00000000-0000-0000-0000-000000000000"),
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        proforma_number="PREVIEW",
        issue_date=payload.issue_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=pi_subtotal,
        discount_total=pi_discount,
        cgst_amount=pi_cgst,
        sgst_amount=pi_sgst,
        igst_amount=pi_igst,
        utgst_amount=pi_utgst,
        cess_amount=pi_cess,
        total=grand_total,
        pos_state_code=payload.pos_state_code,
        lines=db_lines,
        contact=contact
    )
    return pi


@router.get("", response_model=List[ProformaInvoiceListResponse])
def list_proforma_invoices(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(ProformaInvoice, Contact.name.label("contact_name"))\
        .join(Contact, ProformaInvoice.contact_id == Contact.id)\
        .filter(ProformaInvoice.tenant_id == tenant_id, ProformaInvoice.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for pi, contact_name in results:
        response.append(ProformaInvoiceListResponse(
            id=pi.id,
            proforma_number=pi.proforma_number,
            issue_date=pi.issue_date,
            due_date=pi.due_date,
            status=pi.status,
            total=pi.total,
            contact_name=contact_name,
            created_at=pi.created_at
        ))
    return response


@router.get("/{id}", response_model=ProformaInvoiceResponse)
def get_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")
    return pi


@router.put("/{id}", response_model=ProformaInvoiceResponse)
def update_proforma_invoice(
    id: uuid.UUID,
    payload: ProformaInvoiceUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")

    if pi.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft proforma invoices can be modified.")

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Customer not found in this context.")
        pi.contact_id = payload.contact_id
        
    if payload.proforma_number:
        pi.proforma_number = payload.proforma_number
    if payload.issue_date:
        pi.issue_date = payload.issue_date
    if payload.due_date:
        pi.due_date = payload.due_date
    if payload.pos_state_code:
        pi.pos_state_code = payload.pos_state_code

    if payload.line_items is not None:
        db.query(ProformaInvoiceLine).filter(ProformaInvoiceLine.proforma_invoice_id == id).delete()

        contact = db.query(Contact).filter(Contact.id == pi.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)
        db_lines = []
        pi_subtotal = Decimal("0.0000")
        pi_cgst = Decimal("0.0000")
        pi_sgst = Decimal("0.0000")
        pi_igst = Decimal("0.0000")
        pi_utgst = Decimal("0.0000")
        pi_cess = Decimal("0.0000")
        pi_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            if line_subtotal < 0:
                raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=pi.pos_state_code,
                base_amount=line_subtotal,
                gst_rate=line.gst_rate
            )

            db_line = ProformaInvoiceLine(
                proforma_invoice_id=pi.id,
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

            pi_subtotal += db_line.subtotal
            pi_cgst += db_line.cgst_amount
            pi_sgst += db_line.sgst_amount
            pi_igst += db_line.igst_amount
            pi_utgst += db_line.utgst_amount
            pi_cess += db_line.cess_amount
            pi_discount += db_line.discount

        pi.subtotal = pi_subtotal
        pi.discount_total = pi_discount
        pi.cgst_amount = pi_cgst
        pi.sgst_amount = pi_sgst
        pi.igst_amount = pi_igst
        pi.utgst_amount = pi_utgst
        pi.cess_amount = pi_cess
        pi.total = pi_subtotal + pi_cgst + pi_sgst + pi_igst + pi_utgst + pi_cess
        pi.lines = db_lines

    db.commit()
    db.refresh(pi)
    return pi


@router.post("/{id}/issue", response_model=ProformaInvoiceResponse)
def issue_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")

    if pi.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft proforma invoices can be issued.")

    # Note: Proforma invoices typically don't create ledger entries upon issuance
    # They serve as quotations that later get converted to sales invoices
    pi.status = "ISSUED"
    db.commit()
    db.refresh(pi)
    return pi


@router.post("/{id}/convert", response_model=ProformaInvoiceResponse)
def convert_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found in this company context.")

    if pi.status != "ISSUED":
        raise HTTPException(status_code=400, detail="Only issued proforma invoices can be converted.")

    # Create actual Invoice from proforma data
    from src.infrastructure.database.models import Invoice, InvoiceLine
    from src.domains.company.services import NumberingSeriesService

    inv_number = NumberingSeriesService.generate_number(db, tenant_id, "INVOICE")

    invoice = Invoice(
        tenant_id=tenant_id,
        contact_id=pi.contact_id,
        invoice_number=inv_number,
        issue_date=date.today(),
        due_date=date.today(),
        status="DRAFT",
        subtotal=pi.subtotal,
        discount_total=pi.discount_total,
        cgst_amount=pi.cgst_amount,
        sgst_amount=pi.sgst_amount,
        igst_amount=pi.igst_amount,
        utgst_amount=pi.utgst_amount,
        cess_amount=pi.cess_amount,
        total=pi.total,
        pos_state_code=pi.pos_state_code,
    )
    db.add(invoice)
    db.flush()

    # Copy line items
    for pl in pi.lines:
        inv_line = InvoiceLine(
            invoice_id=invoice.id,
            product_id=pl.product_id,
            description=pl.description,
            quantity=pl.quantity,
            rate=pl.rate,
            discount=pl.discount,
            subtotal=pl.subtotal,
            hsn_sac=pl.hsn_sac,
            gst_rate=pl.gst_rate,
            cgst_rate=pl.cgst_rate,
            cgst_amount=pl.cgst_amount,
            sgst_rate=pl.sgst_rate,
            sgst_amount=pl.sgst_amount,
            igst_rate=pl.igst_rate,
            igst_amount=pl.igst_amount,
            utgst_rate=pl.utgst_rate,
            utgst_amount=pl.utgst_amount,
            cess_rate=pl.cess_rate,
            cess_amount=pl.cess_amount,
            total=pl.total,
        )
        db.add(inv_line)

    # Link proforma to invoice
    pi.converted_to_invoice_id = invoice.id
    pi.status = "CONVERTED"
    db.commit()
    db.refresh(pi)
    return pi


@router.post("/{id}/cancel", response_model=ProformaInvoiceResponse)
def cancel_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma Invoice not found.")

    if pi.status in ("CONVERTED", "CANCELLED"):
        raise HTTPException(status_code=400, detail="Cannot convert or cancel already cancelled proforma invoices.")

    pi.status = "CANCELLED"
    db.commit()
    db.refresh(pi)
    return pi

@router.get("/{id}/pdf-payload")
def get_proforma_invoice_pdf_payload(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma invoice not found.")

    settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    company = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    bank = db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_primary == True,
        BankingProfile.is_active == True
    ).first()
    contact = pi.contact

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
        "proforma_invoice": {
            "id": str(pi.id),
            "proforma_number": pi.proforma_number,
            "issue_date": pi.issue_date.isoformat(),
            "due_date": pi.due_date.isoformat(),
            "pos_state_code": pi.pos_state_code,
            "status": pi.status,
            "subtotal": str(pi.subtotal.quantize(Decimal("0.01"))),
            "discount_total": str(pi.discount_total.quantize(Decimal("0.01"))),
            "cgst_amount": str(pi.cgst_amount.quantize(Decimal("0.01"))),
            "sgst_amount": str(pi.sgst_amount.quantize(Decimal("0.01"))),
            "igst_amount": str(pi.igst_amount.quantize(Decimal("0.01"))),
            "utgst_amount": str(pi.utgst_amount.quantize(Decimal("0.01"))),
            "cess_amount": str(pi.cess_amount.quantize(Decimal("0.01"))),
            "total": str(pi.total.quantize(Decimal("0.01")))
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
            for line in pi.lines
        ]
    }


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_proforma_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete"))
):
    pi = db.query(ProformaInvoice).filter(
        ProformaInvoice.id == id,
        ProformaInvoice.tenant_id == tenant_id,
        ProformaInvoice.deleted_at == None
    ).first()
    if not pi:
        raise HTTPException(status_code=404, detail="Proforma invoice not found.")
    
    if pi.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only draft estimates/proforma invoices can be deleted."
        )
    
    pi.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return