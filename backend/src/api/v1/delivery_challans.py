from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from datetime import date
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    DeliveryChallan, DeliveryChallanLine, SalesOrder, Invoice, InvoiceLine,
    StockLedger,
    Contact, Product, JournalEntry, JournalLine
)
from src.schemas.bill_schemas import (
    DeliveryChallanCreate, DeliveryChallanUpdate, DeliveryChallanResponse, DeliveryChallanListResponse
)
from src.schemas.document import InvoiceResponse
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine
from src.domains.company.services import resolve_origin_state_code, NumberingSeriesService
from src.domains.inventory.services import resolve_default_warehouse_id, get_warehouse_stock
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
    ).with_for_update().first()
    if not contact:
        raise HTTPException(status_code=404, detail="Customer not found in this company context.")
    
    if contact.contact_type not in ("CUSTOMER", "BOTH"):
        raise HTTPException(status_code=400, detail="Selected contact must be a Customer.")
    if not contact.is_active:
        raise HTTPException(status_code=400, detail="Selected customer is inactive.")

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
            gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
        )

        db_line = DeliveryChallanLine(
            product_id=line.product_id,
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

        dc_subtotal += db_line.subtotal
        dc_cgst += db_line.cgst_amount
        dc_sgst += db_line.sgst_amount
        dc_igst += db_line.igst_amount
        dc_utgst += db_line.utgst_amount
        dc_cess += db_line.cess_amount
        dc_discount += db_line.discount

    grand_total = dc_subtotal + dc_cgst + dc_sgst + dc_igst + dc_utgst + dc_cess

    challan_number = payload.challan_number
    if not challan_number:
        challan_number = NumberingSeriesService.generate_next_number(db, tenant_id, "DELIVERY_CHALLAN")

    dc = DeliveryChallan(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        challan_number=challan_number,
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
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create delivery challan: {str(e)}")
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
        .order_by(DeliveryChallan.challan_date.desc(), DeliveryChallan.created_at.desc())\
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
    ).with_for_update().first()
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
                gst_rate=GSTEngine.resolve_gst_rate(db, tenant_id, line.gst_rate)
            )

            db_line = DeliveryChallanLine(
                delivery_challan_id=dc.id,
                product_id=line.product_id,
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

    # Dispatch is the physical stock event. The later invoice records revenue/GST
    # but deliberately does not move the same stock a second time.
    quantities_by_product = {}
    rates_by_product = {}
    for line in dc.lines:
        if line.product_id and line.quantity:
            quantities_by_product[line.product_id] = (
                quantities_by_product.get(line.product_id, Decimal("0")) + line.quantity
            )
            rates_by_product[line.product_id] = line.rate
    for product_id, quantity in quantities_by_product.items():
        product = db.query(Product).filter(
            Product.id == product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).with_for_update().first()
        if product and product.product_type == "GOODS":
            available = product.current_stock or Decimal("0")
            warehouse_id = resolve_default_warehouse_id(db, tenant_id)
            location_available = get_warehouse_stock(
                db, tenant_id, warehouse_id, product_id
            )
            effective_available = location_available if location_available is not None else available
            if effective_available < quantity:
                raise HTTPException(
                    status_code=422,
                    detail=f"Insufficient stock for {product.name} in the default warehouse. Available: {effective_available}, Required: {quantity}",
                )
            product.current_stock = available - quantity
            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product_id,
                warehouse_id=warehouse_id,
                reference_type="DELIVERY_CHALLAN",
                reference_id=dc.id,
                quantity=-quantity,
                balance_quantity=product.current_stock,
                rate=rates_by_product[product_id],
            ))
    dc.status = "ISSUED"
    if dc.source_sales_order_id:
        order = db.query(SalesOrder).filter(
            SalesOrder.id == dc.source_sales_order_id,
            SalesOrder.tenant_id == tenant_id,
            SalesOrder.deleted_at == None,
        ).with_for_update().first()
        if order:
            order.status = "DELIVERED"
    db.commit()
    db.refresh(dc)
    return dc


@router.post("/{id}/convert-to-invoice", response_model=InvoiceResponse)
def convert_delivery_challan_to_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("sales:convert")),
):
    dc = db.query(DeliveryChallan).filter(
        DeliveryChallan.id == id,
        DeliveryChallan.tenant_id == tenant_id,
        DeliveryChallan.deleted_at == None,
    ).with_for_update().first()
    if not dc:
        raise HTTPException(status_code=404, detail="Delivery Challan not found.")
    if dc.converted_to_invoice_id:
        existing = db.query(Invoice).filter(
            Invoice.id == dc.converted_to_invoice_id,
            Invoice.tenant_id == tenant_id,
    ).with_for_update().first()
        if existing:
            return existing
    if dc.status != "ISSUED":
        raise HTTPException(status_code=400, detail="Only issued delivery challans can be invoiced.")

    invoice = Invoice(
        tenant_id=tenant_id, contact_id=dc.contact_id,
        source_document_type="DELIVERY_CHALLAN", source_document_id=dc.id,
        invoice_number=NumberingSeriesService.generate_next_number(db, tenant_id, "INVOICE"),
        issue_date=date.today(), due_date=max(dc.due_date, date.today()), status="DRAFT",
        subtotal=dc.subtotal, discount_total=Decimal("0.0000"),
        cgst_amount=dc.cgst_amount, sgst_amount=dc.sgst_amount,
        igst_amount=dc.igst_amount, utgst_amount=dc.utgst_amount,
        cess_amount=dc.cess_amount, total=dc.total,
        pos_state_code=dc.pos_state_code, reference_number=dc.challan_number,
        lines=[InvoiceLine(
            product_id=line.product_id, description=line.description,
            quantity=line.quantity, rate=line.rate, discount=line.discount,
            subtotal=line.subtotal, hsn_sac=line.hsn_sac, gst_rate=line.gst_rate,
            cgst_rate=line.cgst_rate, cgst_amount=line.cgst_amount,
            sgst_rate=line.sgst_rate, sgst_amount=line.sgst_amount,
            igst_rate=line.igst_rate, igst_amount=line.igst_amount,
            utgst_rate=line.utgst_rate, utgst_amount=line.utgst_amount,
            cess_rate=line.cess_rate, cess_amount=line.cess_amount, total=line.total,
        ) for line in dc.lines],
    )
    db.add(invoice)
    db.flush()
    dc.converted_to_invoice_id = invoice.id
    if dc.source_sales_order_id:
        order = db.query(SalesOrder).filter(
            SalesOrder.id == dc.source_sales_order_id,
            SalesOrder.tenant_id == tenant_id,
        ).first()
        if order:
            order.converted_to_invoice_id = invoice.id
    db.commit()
    db.refresh(invoice)
    return invoice


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
    ).with_for_update().first()
    if not dc:
        raise HTTPException(status_code=404, detail="Delivery Challan not found.")

    if dc.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Delivery challan is already cancelled.")
    if dc.converted_to_invoice_id:
        raise HTTPException(
            status_code=409,
            detail="An invoiced delivery cannot be cancelled. Use a credit note/return workflow.",
        )

    stock_moves = db.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "DELIVERY_CHALLAN",
        StockLedger.reference_id == dc.id,
    ).all()
    for move in stock_moves:
        product = db.query(Product).filter(
            Product.id == move.product_id,
            Product.tenant_id == tenant_id,
        ).with_for_update().first()
        if product:
            restore_quantity = -move.quantity
            product.current_stock = (product.current_stock or Decimal("0")) + restore_quantity
            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=move.product_id,
                warehouse_id=move.warehouse_id,
                reference_type="DELIVERY_CHALLAN_REVERSAL",
                reference_id=dc.id,
                quantity=restore_quantity,
                balance_quantity=product.current_stock,
                rate=move.rate,
            ))

    dc.status = "CANCELLED"
    db.commit()
    db.refresh(dc)
    return dc
