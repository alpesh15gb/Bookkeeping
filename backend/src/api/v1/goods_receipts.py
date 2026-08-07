from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session, joinedload
from typing import List
import uuid
from datetime import date, datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    GoodsReceipt, GoodsReceiptLine, PurchaseOrder, PurchaseOrderLine,
    Contact, Product, Branch, StockLedger,
)
from src.schemas.goods_receipt_schemas import (
    GoodsReceiptCreate, GoodsReceiptResponse, GoodsReceiptListResponse,
    PaginatedGoodsReceiptResponse,
)
from src.api.deps import enforce_permission

router = APIRouter(prefix="/goods-receipts", tags=["Goods Receipts (GRN)"])


# ── Helpers ──────────────────────────────────────────────────────────────────

def _resolve_po_details(db: Session, tenant_id: uuid.UUID, purchase_order_id: uuid.UUID | None) -> tuple:
    """Return (contact_id, po_number) from a purchase order, or (None, None)."""
    if purchase_order_id is None:
        return None, None
    po = db.query(PurchaseOrder).filter(
        PurchaseOrder.id == purchase_order_id,
        PurchaseOrder.tenant_id == tenant_id,
        PurchaseOrder.deleted_at == None,
    ).first()
    if not po:
        raise HTTPException(status_code=404, detail="Purchase order not found.")
    return po.contact_id, po.po_number


def _build_response(gr: GoodsReceipt, po_number: str | None = None, contact_name: str | None = None) -> GoodsReceiptResponse:
    lines_out = []
    for line in gr.lines:
        product_name = line.product.name if line.product else None
        warehouse_name = line.warehouse.name if line.warehouse else None
        lines_out.append(GoodsReceiptLineResponse(
            id=line.id,
            purchase_order_line_id=line.purchase_order_line_id,
            product_id=line.product_id,
            quantity_ordered=line.quantity_ordered,
            quantity_received=line.quantity_received,
            warehouse_id=line.warehouse_id,
            lot_number=line.lot_number,
            batch_number=line.batch_number,
            product_name=product_name,
            warehouse_name=warehouse_name,
        ))
    return GoodsReceiptResponse(
        id=gr.id,
        tenant_id=gr.tenant_id,
        contact_id=gr.contact_id,
        receipt_number=gr.receipt_number,
        receipt_date=gr.receipt_date,
        status=gr.status,
        purchase_order_id=gr.purchase_order_id,
        po_number=po_number or "",
        contact_name=contact_name,
        notes=gr.notes,
        lines=lines_out,
        created_at=gr.created_at,
        confirmed_at=gr.confirmed_at,
        cancelled_at=gr.cancelled_at,
    )


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("", response_model=GoodsReceiptResponse, status_code=status.HTTP_201_CREATED)
def create_goods_receipt(
    payload: GoodsReceiptCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("purchase_order:create")),
):
    contact_id, po_number = _resolve_po_details(db, tenant_id, payload.purchase_order_id)

    # Generate receipt number — simplest approach: timestamp-based
    today = date.today()
    count = db.query(GoodsReceipt).filter(
        GoodsReceipt.tenant_id == tenant_id,
        GoodsReceipt.receipt_date == today,
    ).count()
    receipt_number = f"GRN-{today.strftime('%Y%m%d')}-{count + 1:04d}"

    gr = GoodsReceipt(
        tenant_id=tenant_id,
        purchase_order_id=payload.purchase_order_id,
        contact_id=contact_id,
        receipt_number=receipt_number,
        receipt_date=payload.receipt_date,
        status="DRAFT",
        notes=payload.notes,
    )
    db.add(gr)
    db.flush()

    for line_in in payload.lines:
        product = db.query(Product).filter(
            Product.id == line_in.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
            Product.is_active == True,
        ).first()
        if product is None:
            raise HTTPException(
                status_code=400,
                detail=f"Product {line_in.product_id} was not found.",
            )
        if line_in.quantity_received <= 0:
            raise HTTPException(
                status_code=400,
                detail="Received quantity must be greater than zero.",
            )
        line = GoodsReceiptLine(
            goods_receipt_id=gr.id,
            purchase_order_line_id=line_in.purchase_order_line_id,
            product_id=line_in.product_id,
            quantity_ordered=line_in.quantity_ordered,
            quantity_received=line_in.quantity_received,
            warehouse_id=line_in.warehouse_id,
            lot_number=line_in.lot_number,
            batch_number=line_in.batch_number,
        )
        db.add(line)

    db.commit()
    db.refresh(gr)

    contact_name = gr.contact.name if gr.contact else None
    return _build_response(gr, po_number, contact_name)


@router.get("", response_model=PaginatedGoodsReceiptResponse)
def list_goods_receipts(
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view")),
):
    offset = (page - 1) * limit
    q = db.query(GoodsReceipt).options(
        joinedload(GoodsReceipt.contact),
        joinedload(GoodsReceipt.purchase_order),
    ).filter(
        GoodsReceipt.tenant_id == tenant_id,
        GoodsReceipt.deleted_at == None,
    )

    total = q.count()
    results = q.order_by(GoodsReceipt.created_at.desc()).offset(offset).limit(limit).all()

    items = []
    for gr in results:
        po_number = gr.purchase_order.po_number if gr.purchase_order else ""
        contact_name = gr.contact.name if gr.contact else ""
        items.append(GoodsReceiptListResponse(
            id=gr.id,
            receipt_number=gr.receipt_number,
            receipt_date=gr.receipt_date,
            status=gr.status,
            po_number=po_number,
            contact_name=contact_name,
            created_at=gr.created_at,
        ))

    return PaginatedGoodsReceiptResponse(items=items, total=total, page=page, limit=limit)


@router.get("/{id}", response_model=GoodsReceiptResponse)
def get_goods_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view")),
):
    gr = db.query(GoodsReceipt).options(
        joinedload(GoodsReceipt.contact),
        joinedload(GoodsReceipt.purchase_order),
        joinedload(GoodsReceipt.lines).joinedload(GoodsReceiptLine.product),
        joinedload(GoodsReceipt.lines).joinedload(GoodsReceiptLine.warehouse),
    ).filter(
        GoodsReceipt.id == id,
        GoodsReceipt.tenant_id == tenant_id,
        GoodsReceipt.deleted_at == None,
    ).first()

    if not gr:
        raise HTTPException(status_code=404, detail="Goods receipt not found.")

    po_number = gr.purchase_order.po_number if gr.purchase_order else ""
    contact_name = gr.contact.name if gr.contact else ""
    return _build_response(gr, po_number, contact_name)


@router.post("/{id}/confirm", response_model=GoodsReceiptResponse)
def confirm_goods_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("purchase_order:create")),
):
    gr = db.query(GoodsReceipt).options(
        joinedload(GoodsReceipt.contact),
        joinedload(GoodsReceipt.purchase_order),
        joinedload(GoodsReceipt.lines).joinedload(GoodsReceiptLine.product),
        joinedload(GoodsReceipt.lines).joinedload(GoodsReceiptLine.warehouse),
    ).filter(
        GoodsReceipt.id == id,
        GoodsReceipt.tenant_id == tenant_id,
        GoodsReceipt.deleted_at == None,
    ).first()

    if not gr:
        raise HTTPException(status_code=404, detail="Goods receipt not found.")
    if gr.status != "DRAFT":
        raise HTTPException(status_code=400, detail=f"Cannot confirm goods receipt in status '{gr.status}'.")

    for line in gr.lines:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if product is None:
            raise HTTPException(
                status_code=409,
                detail=f"Product {line.product_id} is no longer available.",
            )

        # Use the rate from the linked purchase order line if available,
        # otherwise fall back to product master purchase price
        rate = product.purchase_price
        if line.purchase_order_line_id:
            po_line = db.query(PurchaseOrderLine).filter(
                PurchaseOrderLine.id == line.purchase_order_line_id
            ).first()
            if po_line:
                rate = po_line.rate

        product.current_stock += line.quantity_received
        db.add(StockLedger(
            tenant_id=tenant_id,
            product_id=product.id,
            warehouse_id=line.warehouse_id,
            quantity=line.quantity_received,
            balance_quantity=product.current_stock,
            reference_type="GOODS_RECEIPT",
            reference_id=gr.id,
            rate=rate,
        ))

    gr.status = "CONFIRMED"
    gr.confirmed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(gr)

    po_number = gr.purchase_order.po_number if gr.purchase_order else ""
    contact_name = gr.contact.name if gr.contact else ""
    return _build_response(gr, po_number, contact_name)


@router.post("/{id}/cancel", response_model=GoodsReceiptResponse)
def cancel_goods_receipt(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("purchase_order:create")),
):
    gr = db.query(GoodsReceipt).options(
        joinedload(GoodsReceipt.contact),
        joinedload(GoodsReceipt.purchase_order),
        joinedload(GoodsReceipt.lines).joinedload(GoodsReceiptLine.product),
        joinedload(GoodsReceipt.lines).joinedload(GoodsReceiptLine.warehouse),
    ).filter(
        GoodsReceipt.id == id,
        GoodsReceipt.tenant_id == tenant_id,
        GoodsReceipt.deleted_at == None,
    ).first()

    if not gr:
        raise HTTPException(status_code=404, detail="Goods receipt not found.")
    if gr.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Goods receipt is already cancelled.")
    if gr.status not in ("DRAFT", "CONFIRMED"):
        raise HTTPException(status_code=400, detail=f"Cannot cancel goods receipt in status '{gr.status}'.")

    if gr.status == "CONFIRMED":
        for line in gr.lines:
            product = db.query(Product).filter(
                Product.id == line.product_id,
                Product.tenant_id == tenant_id,
                Product.deleted_at == None,
            ).first()
            if product is None:
                raise HTTPException(
                    status_code=409,
                    detail=f"Product {line.product_id} is no longer available.",
                )
            if product.current_stock < line.quantity_received:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"Cannot cancel: {product.name} stock has already "
                        "been consumed."
                    ),
                )
            product.current_stock -= line.quantity_received

            # Use the rate from the linked purchase order line if available,
            # otherwise fall back to product master purchase price
            rate = product.purchase_price
            if line.purchase_order_line_id:
                po_line = db.query(PurchaseOrderLine).filter(
                    PurchaseOrderLine.id == line.purchase_order_line_id
                ).first()
                if po_line:
                    rate = po_line.rate

            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product.id,
                warehouse_id=line.warehouse_id,
                quantity=-line.quantity_received,
                balance_quantity=product.current_stock,
                reference_type="GOODS_RECEIPT_CANCEL",
                reference_id=gr.id,
                rate=rate,
            ))

    gr.status = "CANCELLED"
    gr.cancelled_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(gr)

    po_number = gr.purchase_order.po_number if gr.purchase_order else ""
    contact_name = gr.contact.name if gr.contact else ""
    return _build_response(gr, po_number, contact_name)
