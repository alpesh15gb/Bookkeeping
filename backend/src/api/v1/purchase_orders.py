from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    PurchaseOrder, PurchaseOrderLine, Contact, Product, JournalEntry, JournalLine
)
from src.schemas.bill_schemas import (
    PurchaseOrderCreate, PurchaseOrderUpdate, PurchaseOrderResponse, PurchaseOrderListResponse
)
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import get_tenant_context, enforce_permission

router = APIRouter(prefix="/purchase-orders", tags=["Purchase Orders"])


@router.post("", response_model=PurchaseOrderResponse, status_code=status.HTTP_201_CREATED)
def create_purchase_order(
    payload: PurchaseOrderCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create"))  # Reusing invoice:create permission for now
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

    # Use vendor's state code if available, otherwise fallback to company's origin state
    origin_state_code = contact.state_code or resolve_origin_state_code(db, tenant_id)

    db_lines = []
    po_subtotal = Decimal("0.0000")
    po_cgst = Decimal("0.0000")
    po_sgst = Decimal("0.0000")
    po_igst = Decimal("0.0000")
    po_utgst = Decimal("0.0000")
    po_cess = Decimal("0.0000")
    po_discount = Decimal("0.0000")

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

        db_line = PurchaseOrderLine(
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

        po_subtotal += db_line.subtotal
        po_cgst += db_line.cgst_amount
        po_sgst += db_line.sgst_amount
        po_igst += db_line.igst_amount
        po_utgst += db_line.utgst_amount
        po_cess += db_line.cess_amount
        po_discount += db_line.discount

    grand_total = po_subtotal + po_cgst + po_sgst + po_igst + po_utgst + po_cess

    po = PurchaseOrder(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        po_number=payload.po_number,
        order_date=payload.order_date,
        due_date=payload.due_date,
        status="DRAFT",
        subtotal=po_subtotal,
        discount_total=po_discount,
        cgst_amount=po_cgst,
        sgst_amount=po_sgst,
        igst_amount=po_igst,
        utgst_amount=po_utgst,
        cess_amount=po_cess,
        total=grand_total,
        amount_received=Decimal("0.0000"),
        pos_state_code=payload.pos_state_code,
        lines=db_lines
    )

    db.add(po)
    db.commit()
    db.refresh(po)
    return po


@router.get("", response_model=List[PurchaseOrderListResponse])
def list_purchase_orders(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    results = db.query(PurchaseOrder, Contact.name.label("contact_name"))\
        .join(Contact, PurchaseOrder.contact_id == Contact.id)\
        .filter(PurchaseOrder.tenant_id == tenant_id, PurchaseOrder.deleted_at == None)\
        .offset(offset).limit(limit).all()

    response = []
    for po, contact_name in results:
        response.append(PurchaseOrderListResponse(
            id=po.id,
            po_number=po.po_number,
            order_date=po.order_date,
            due_date=po.due_date,
            status=po.status,
            total=po.total,
            amount_received=po.amount_received,
            contact_name=contact_name,
            created_at=po.created_at
        ))
    return response


@router.get("/{id}", response_model=PurchaseOrderResponse)
def get_purchase_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    po = db.query(PurchaseOrder).filter(
        PurchaseOrder.id == id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.deleted_at == None
    ).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found in this company context.")
    return po


@router.put("/{id}", response_model=PurchaseOrderResponse)
def update_purchase_order(
    id: uuid.UUID,
    payload: PurchaseOrderUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update"))
):
    po = db.query(PurchaseOrder).filter(
        PurchaseOrder.id == id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.deleted_at == None
    ).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found in this company context.")

    if po.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft purchase orders can be modified.")

    if payload.contact_id:
        contact = db.query(Contact).filter(Contact.id == payload.contact_id, Contact.tenant_id == tenant_id).first()
        if not contact:
            raise HTTPException(status_code=400, detail="Vendor not found in this context.")
        po.contact_id = payload.contact_id
        
    if payload.po_number:
        po.po_number = payload.po_number
    if payload.order_date:
        po.order_date = payload.order_date
    if payload.due_date:
        po.due_date = payload.due_date
    if payload.pos_state_code:
        po.pos_state_code = payload.pos_state_code

    if payload.line_items is not None:
        db.query(PurchaseOrderLine).filter(PurchaseOrderLine.purchase_order_id == id).delete()

        contact = db.query(Contact).filter(Contact.id == po.contact_id).first()
        origin_state_code = contact.state_code if (contact and contact.state_code) else resolve_origin_state_code(db, tenant_id)
        db_lines = []
        po_subtotal = Decimal("0.0000")
        po_cgst = Decimal("0.0000")
        po_sgst = Decimal("0.0000")
        po_igst = Decimal("0.0000")
        po_utgst = Decimal("0.0000")
        po_cess = Decimal("0.0000")
        po_discount = Decimal("0.0000")

        for line in payload.line_items:
            product = db.query(Product).filter(Product.id == line.product_id, Product.tenant_id == tenant_id).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product with ID {line.product_id} not found in this context.")

            line_subtotal = (line.quantity * line.rate) - line.discount
            if line_subtotal < 0:
                raise HTTPException(status_code=400, detail="Line item subtotal cannot be negative.")

            tax_split = GSTEngine.calculate_tax(
                origin_state_code=origin_state_code,
                place_of_supply_state_code=po.pos_state_code,
                base_amount=line_subtotal,
                gst_rate=line.gst_rate
            )

            db_line = PurchaseOrderLine(
                purchase_order_id=po.id,
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

            po_subtotal += db_line.subtotal
            po_cgst += db_line.cgst_amount
            po_sgst += db_line.sgst_amount
            po_igst += db_line.igst_amount
            po_utgst += db_line.utgst_amount
            po_cess += db_line.cess_amount
            po_discount += db_line.discount

        po.subtotal = po_subtotal
        po.discount_total = po_discount
        po.cgst_amount = po_cgst
        po.sgst_amount = po_sgst
        po.igst_amount = po_igst
        po.utgst_amount = po_utgst
        po.cess_amount = po_cess
        po.total = po_subtotal + po_cgst + po_sgst + po_igst + po_utgst + po_cess
        po.lines = db_lines

    db.commit()
    db.refresh(po)
    return po


@router.post("/{id}/confirm", response_model=PurchaseOrderResponse)
def confirm_purchase_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    po = db.query(PurchaseOrder).filter(
        PurchaseOrder.id == id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.deleted_at == None
    ).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found in this company context.")

    if po.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft purchase orders can be confirmed.")

    # Note: Purchase orders typically don't create ledger entries upon confirmation
    # They become commitments that later get converted to bills when goods are received
    po.status = "CONFIRMED"
    db.commit()
    db.refresh(po)
    return po


@router.post("/{id}/receive", response_model=PurchaseOrderResponse)
def receive_purchase_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    po = db.query(PurchaseOrder).filter(
        PurchaseOrder.id == id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.deleted_at == None
    ).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found in this company context.")

    if po.status not in ("DRAFT", "CONFIRMED"):
        raise HTTPException(status_code=400, detail="Only draft or confirmed purchase orders can be marked as received.")

    # When received, we update the amount received but don't create ledger entries yet
    # Ledger entries happen when the bill is created from this PO
    po.status = "RECEIVED"
    db.commit()
    db.refresh(po)
    return po


@router.post("/{id}/cancel", response_model=PurchaseOrderResponse)
def cancel_purchase_order(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    po = db.query(PurchaseOrder).filter(
        PurchaseOrder.id == id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.deleted_at == None
    ).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase Order not found.")

    if po.status in ("RECEIVED", "CANCELLED"):
        raise HTTPException(status_code=400, detail="Cannot cancel received or already cancelled purchase orders.")

    po.status = "CANCELLED"
    db.commit()
    db.refresh(po)
    return po