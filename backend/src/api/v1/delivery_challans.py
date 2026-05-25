from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    DeliveryChallan, DeliveryChallanLine, Contact, Product, JournalEntry, JournalLine
)
from src.schemas.bill_schemas import (
    DeliveryChallanCreate, DeliveryChallanUpdate, DeliveryChallanResponse, DeliveryChallanListResponse
)
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/delivery-challans", tags=["Delivery Challans"])


@router.post("", response_model=DeliveryChallanResponse, status_code=status.HTTP_201_CREATED)
def create_delivery_challan(
    payload: DeliveryChallanCreate,
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
    dc_subtotal = Decimal("0.0000")
    dc_cgst = Decimal("0.0000")
    dc_sgst = Decimal("0.0000")
    dc_igst = Decimal("0.0000")
    dc_utgst = Decimal("0.0000")
    dc_cess = Decimal("0.0000")
    dc_discount = Decimal("0.0000")

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

        db_line = DeliveryChallanLine(
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

        dc_subtotal += db_line.subtotal
        dc_cgst += db_line.cgst_amount
        dc_sgst += db_line.sgst_amount
        dc_igst += db_line.igst_amount
        dc_utgst += db_line.utgst_amount
        dc_cess += db_line.cess_amount
        dc_discount += db_line.discount

    grand_total = dc_subtotal + dc_cgst + dc_sgst + dc_igst + dc_utgst + dc_cess

    dc = DeliveryChallan(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        challan_number=payload.challan_number,
        challan_date=payload.challan_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=dc_subtotal,
        discount_total=dc_discount,
        cgst_amount=dc_cgst,
        sgst_amount=dc_sgst,
        igst_amount=dc_igst,
        utgst_amount=dc_utgst,
        cess_amount=dc_cess,
        total=grand_total,
        pos_state_code=payload.pos_state_code,
        lines=db_lines
    )

    db.add(dc)
    db.commit()
    db.refresh(dc)
    return dc


@router.get("", response_model=List[DeliveryChallanListResponse])
def list_delivery_challans(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(DeliveryChallan, Contact.name.label("contact_name"))\
        .join(Contact, DeliveryChallan.contact_id == Contact.id)\
        .filter(DeliveryChallan.tenant_id == tenant_id, DeliveryChallan.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for dc, contact_name in results:
        response.append(DeliveryChallanListResponse(
            id=dc.id,
            challan_number=dc.challan_number,
            challan_date=dc.challan_date,
            due_date=dc.due_date,
            status=dc.status,
            total=dc.total,
            contact_name=contact_name,
            created_at=dc.created_at
        ))
    return response


@router.get("/{id}", response_model=DeliveryChallanResponse)
def get_delivery_challan(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    dc = db.query(DeliveryChallan).filter(
        DeliveryChallan.id == id,
        DeliveryChallan.tenant_id == tenant_id,
        DeliveryChallan.deleted_at == None
    ).first()
    if not dc:
        raise HTTPException(status_code=404, detail="Delivery Challan not found in this company context.")
    return dc


@router.put("/{id}", response_model=DeliveryChallanResponse)
def update_delivery_challan(
    id: uuid.UUID,
    payload: DeliveryChallanUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    dc = db.query(DeliveryChallan).filter(
        DeliveryChallan.id == id,
        DeliveryChallan.tenant_id == tenant_id,
        DeliveryChallan.deleted_at == None
    ).first()
    if not dc:
        raise HTTPException(status_code=404, detail="Delivery Challan not found in this company context.")

    if dc.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft delivery challans can be modified.")

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Customer not found in this context.")
        dc.contact_id = payload.contact_id
        
    if payload.challan_number:
        dc.challan_number = payload.challan_number
    if payload.challan_date:
        dc.challan_date = payload.challan_date
    if payload.due_date:
        dc.due_date = payload.due_date
    if payload.pos_state_code:
        dc.pos_state_code = payload.pos_state_code

    if payload.line_items is not None:
        db.query(DeliveryChallanLine).filter(DeliveryChallanLine.delivery_challan_id == id).delete()

        contact = db.query(Contact).filter(Contact.id == dc.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)
        db_lines = []
        dc_subtotal = Decimal("0.0000")
        dc_cgst = Decimal("0.0000")
        dc_sgst = Decimal("0.0000")
        dc_igst = Decimal("0.0000")
        dc_utgst = Decimal("0.0000")
        dc_cess = Decimal("0.0000")
        dc_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            if line_subtotal < 0:
                raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=dc.pos_state_code,
                base_amount=line_subtotal,
                gst_rate=line.gst_rate
            )

            db_line = DeliveryChallanLine(
                delivery_challan_id=dc.id,
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

            dc_subtotal += db_line.subtotal
            dc_cgst += db_line.cgst_amount
            dc_sgst += db_line.sgst_amount
            dc_igst += db_line.igst_amount
            dc_utgst += db_line.utgst_amount
            dc_cess += db_line.cess_amount
            dc_discount += db_line.discount

        dc.subtotal = dc_subtotal
        dc.discount_total = dc_discount
        dc.cgst_amount = dc_cgst
        dc.sgst_amount = dc_sgst
        dc.igst_amount = dc_igst
        dc.utgst_amount = dc_utgst
        dc.cess_amount = dc_cess
        dc.total = dc_subtotal + dc_cgst + dc_sgst + dc_igst + dc_utgst + dc_cess
        dc.lines = db_lines

    db.commit()
    db.refresh(dc)
    return dc


@router.post("/{id}/issue", response_model=DeliveryChallanResponse)
def issue_delivery_challan(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    dc = db.query(DeliveryChallan).filter(
        DeliveryChallan.id == id,
        DeliveryChallan.tenant_id == tenant_id,
        DeliveryChallan.deleted_at == None
    ).first()
    if not dc:
        raise HTTPException(status_code=404, detail="Delivery Challan not found in this company context.")

    if dc.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft delivery challans can be issued.")

    # Note: Delivery challans typically don't create ledger entries upon issuance
    # They serve as delivery documentation that later gets converted to invoices
    dc.status = "ISSUED"
    db.commit()
    db.refresh(dc)
    return dc


@router.post("/{id}/cancel", response_model=DeliveryChallanResponse)
def cancel_delivery_challan(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    dc = db.query(DeliveryChallan).filter(
        DeliveryChallan.id == id,
        DeliveryChallan.tenant_id == tenant_id,
        DeliveryChallan.deleted_at == None
    ).first()
    if not dc:
        raise HTTPException(status_code=404, detail="Delivery Challan not found.")

    if dc.status in ("ISSUED", "CANCELLED"):
        raise HTTPException(status_code=400, detail="Cannot cancel issued or already cancelled delivery challans.")

    dc.status = "CANCELLED"
    db.commit()
    db.refresh(dc)
    return dc