from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    SalesOrder, SalesOrderLine, Contact, Product, JournalEntry, JournalLine,
    TenantSetting, Tenant, BankingProfile
)
from src.schemas.bill_schemas import (
    SalesOrderCreate, SalesOrderUpdate, SalesOrderResponse, SalesOrderListResponse
)
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/sales-orders", tags=["Sales Orders"])


@router.post("", response_model=SalesOrderResponse, status_code=status.HTTP_201_CREATED)
def create_sales_order(
    payload: SalesOrderCreate,
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
    so_subtotal = Decimal("0.0000")
    so_cgst = Decimal("0.0000")
    so_sgst = Decimal("0.0000")
    so_igst = Decimal("0.0000")
    so_utgst = Decimal("0.0000")
    so_cess = Decimal("0.0000")
    so_discount = Decimal("0.0000")

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

        db_line = SalesOrderLine(
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

        so_subtotal += db_line.subtotal
        so_cgst += db_line.cgst_amount
        so_sgst += db_line.sgst_amount
        so_igst += db_line.igst_amount
        so_utgst += db_line.utgst_amount
        so_cess += db_line.cess_amount
        so_discount += db_line.discount

    grand_total = so_subtotal + so_cgst + so_sgst + so_igst + so_utgst + so_cess

    so = SalesOrder(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        so_number=payload.so_number,
        order_date=payload.order_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=so_subtotal,
        discount_total=so_discount,
        cgst_amount=so_cgst,
        sgst_amount=so_sgst,
        igst_amount=so_igst,
        utgst_amount=so_utgst,
        cess_amount=so_cess,
        total=grand_total,
        amount_advanced=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        lines=db_lines
    )

    db.add(so)
    db.commit()
    db.refresh(so)
    return so


@router.get("", response_model=List[SalesOrderListResponse])
def list_sales_orders(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(SalesOrder, Contact.name.label("contact_name"))\
        .join(Contact, SalesOrder.contact_id == Contact.id)\
        .filter(SalesOrder.tenant_id == tenant_id, SalesOrder.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for so, contact_name in results:
        response.append(SalesOrderListResponse(
            id=so.id,
            so_number=so.so_number,
            order_date=so.order_date,
            due_date=so.due_date,
            status=so.status,
            total=so.total,
            amount_advanced=so.amount_advanced,
            contact_name=contact_name,
            created_at=so.created_at
        ))
    return response


@router.get("/{id}", response_model=SalesOrderResponse)
def get_sales_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales Order not found in this company context.")
    return so


@router.get("/{id}/pdf-payload")
def get_sales_order_pdf_payload(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Consolidated metadata for PDF print rendering of a sales order."""
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales Order not found.")

    settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    company = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    bank = db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_primary == True,
        BankingProfile.is_active == True
    ).first()
    contact = so.contact

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
        "sales_order": {
            "id": str(so.id),
            "so_number": so.so_number,
            "order_date": so.order_date.isoformat(),
            "due_date": so.due_date.isoformat(),
            "pos_state_code": so.pos_state_code,
            "status": so.status,
            "subtotal": float(so.subtotal),
            "discount_total": float(so.discount_total),
            "cgst_amount": float(so.cgst_amount),
            "sgst_amount": float(so.sgst_amount),
            "igst_amount": float(so.igst_amount),
            "utgst_amount": float(so.utgst_amount),
            "cess_amount": float(so.cess_amount),
            "total": float(so.total),
            "amount_advanced": float(so.amount_advanced)
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
            for line in so.lines
        ]
    }


@router.put("/{id}", response_model=SalesOrderResponse)
def update_sales_order(
    id: uuid.UUID,
    payload: SalesOrderUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales Order not found in this company context.")

    if so.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft sales orders can be modified.")

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Customer not found in this context.")
        so.contact_id = payload.contact_id
        
    if payload.so_number:
        so.so_number = payload.so_number
    if payload.order_date:
        so.order_date = payload.order_date
    if payload.due_date:
        so.due_date = payload.due_date
    if payload.pos_state_code:
        so.pos_state_code = payload.pos_state_code

    if payload.line_items is not None:
        db.query(SalesOrderLine).filter(SalesOrderLine.sales_order_id == id).delete()

        contact = db.query(Contact).filter(Contact.id == so.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)
        db_lines = []
        so_subtotal = Decimal("0.0000")
        so_cgst = Decimal("0.0000")
        so_sgst = Decimal("0.0000")
        so_igst = Decimal("0.0000")
        so_utgst = Decimal("0.0000")
        so_cess = Decimal("0.0000")
        so_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            if line_subtotal < 0:
                raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=so.pos_state_code,
                base_amount=line_subtotal,
                gst_rate=line.gst_rate
            )

            db_line = SalesOrderLine(
                sales_order_id=so.id,
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

            so_subtotal += db_line.subtotal
            so_cgst += db_line.cgst_amount
            so_sgst += db_line.sgst_amount
            so_igst += db_line.igst_amount
            so_utgst += db_line.utgst_amount
            so_cess += db_line.cess_amount
            so_discount += db_line.discount

        so.subtotal = so_subtotal
        so.discount_total = so_discount
        so.cgst_amount = so_cgst
        so.sgst_amount = so_sgst
        so.igst_amount = so_igst
        so.utgst_amount = so_utgst
        so.cess_amount = so_cess
        so.total = so_subtotal + so_cgst + so_sgst + so_igst + so_utgst + so_cess
        so.lines = db_lines

    db.commit()
    db.refresh(so)
    return so


@router.post("/{id}/confirm", response_model=SalesOrderResponse)
def confirm_sales_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales Order not found in this company context.")

    if so.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft sales orders can be confirmed.")

    # Note: Sales orders typically don't create ledger entries upon confirmation
    # They become commitments that later get converted to invoices when goods are delivered
    so.status = "CONFIRMED"
    db.commit()
    db.refresh(so)
    return so


@router.post("/{id}/deliver", response_model=SalesOrderResponse)
def deliver_sales_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales Order not found in this company context.")

    if so.status not in ("DRAFT", "CONFIRMED"):
        raise HTTPException(status_code=400, detail="Only draft or confirmed sales orders can be marked as delivered.")

    # When delivered, we update the amount delivered but don't create ledger entries yet
    # Ledger entries happen when the invoice is created from this SO
    so.status = "DELIVERED"
    db.commit()
    db.refresh(so)
    return so


@router.post("/{id}/cancel", response_model=SalesOrderResponse)
def cancel_sales_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales Order not found.")

    if so.status in ("DELIVERED", "CANCELLED"):
        raise HTTPException(status_code=400, detail="Cannot cancel delivered or already cancelled sales orders.")

    so.status = "CANCELLED"
    db.commit()
    db.refresh(so)
    return so


@router.get("/{id}/pdf-payload")
def get_so_pdf_payload(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Retrieves metadata model ready for rendering/printing a Sales Order."""
    so = db.query(SalesOrder).filter(
        SalesOrder.id == id,
        SalesOrder.tenant_id == tenant_id,
        SalesOrder.deleted_at == None
    ).first()
    if not so:
        raise HTTPException(status_code=404, detail="Sales order not found.")

    settings = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    company = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    bank = db.query(BankingProfile).filter(
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_primary == True,
        BankingProfile.is_active == True
    ).first()
    contact = so.contact

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
        "sales_order": {
            "id": str(so.id),
            "so_number": so.so_number,
            "order_date": so.order_date.isoformat(),
            "due_date": so.due_date.isoformat(),
            "pos_state_code": so.pos_state_code,
            "status": so.status,
            "subtotal": float(so.subtotal),
            "discount_total": float(so.discount_total),
            "cgst_amount": float(so.cgst_amount),
            "sgst_amount": float(so.sgst_amount),
            "igst_amount": float(so.igst_amount),
            "utgst_amount": float(so.utgst_amount),
            "cess_amount": float(so.cess_amount),
            "total": float(so.total)
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
            for line in so.lines
        ]
    }