"""
Inter-warehouse transfer endpoints.
Follows the same patterns as inventory_adjustments.py.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import uuid
from datetime import datetime, timezone

from src.core.database import get_db_session
from src.infrastructure.database.models import Transfer, Product, StockLedger
from src.schemas.bill_schemas import (
    TransferCreate, TransferUpdate, TransferResponse,
    TransferListResponse, PaginatedTransferResponse,
)
from src.api.deps import enforce_permission

router = APIRouter(prefix="/transfers", tags=["Transfers"])


@router.post("", response_model=TransferResponse, status_code=status.HTTP_201_CREATED)
def create_transfer(
    payload: TransferCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """Create a new inter-warehouse transfer in DRAFT status."""
    # Validate products in lines belong to tenant
    for line in payload.lines:
        product = db.query(Product).filter(
            Product.id == line.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if not product:
            raise HTTPException(
                status_code=400,
                detail=f"Product with ID {line.product_id} not found in this company context.",
            )

    transfer = Transfer(
        tenant_id=tenant_id,
        transfer_number=payload.transfer_number,
        transfer_date=payload.transfer_date,
        from_warehouse_id=payload.from_warehouse_id,
        from_warehouse_name=payload.from_warehouse_name,
        to_warehouse_id=payload.to_warehouse_id,
        to_warehouse_name=payload.to_warehouse_name,
        status="DRAFT",
        lines=[line.model_dump() for line in payload.lines],
        notes=payload.notes,
    )

    db.add(transfer)
    db.commit()
    db.refresh(transfer)
    return transfer


@router.get("", response_model=PaginatedTransferResponse)
def list_transfers(
    page: int = 1,
    limit: int = 50,
    status_filter: str = None,
    search: str = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    """List transfers with server-side pagination."""
    query = db.query(Transfer).filter(
        Transfer.tenant_id == tenant_id,
        Transfer.deleted_at == None,
    )

    if status_filter:
        query = query.filter(Transfer.status == status_filter)

    if search:
        search_pattern = f"%{search}%"
        query = query.filter(
            (Transfer.transfer_number.ilike(search_pattern))
            | (Transfer.from_warehouse_name.ilike(search_pattern))
            | (Transfer.to_warehouse_name.ilike(search_pattern))
        )

    total = query.count()
    offset = (page - 1) * limit
    results = query.order_by(Transfer.created_at.desc()).offset(offset).limit(limit).all()

    items = [
        TransferListResponse(
            id=t.id,
            transfer_number=t.transfer_number or "",
            transfer_date=t.transfer_date or "",
            from_warehouse_name=t.from_warehouse_name or "",
            to_warehouse_name=t.to_warehouse_name or "",
            status=t.status or "DRAFT",
            created_at=t.created_at,
        )
        for t in results
    ]

    return PaginatedTransferResponse(
        items=items,
        total=total,
        page=page,
        limit=limit,
    )


@router.get("/{id}", response_model=TransferResponse)
def get_transfer(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    """Get a single transfer by ID."""
    transfer = db.query(Transfer).filter(
        Transfer.id == id,
        Transfer.tenant_id == tenant_id,
        Transfer.deleted_at == None,
    ).first()
    if not transfer:
        raise HTTPException(status_code=404, detail="Transfer not found in this company context.")
    return transfer


@router.put("/{id}", response_model=TransferResponse)
def update_transfer(
    id: uuid.UUID,
    payload: TransferUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update")),
):
    """Update a DRAFT transfer."""
    transfer = db.query(Transfer).filter(
        Transfer.id == id,
        Transfer.tenant_id == tenant_id,
        Transfer.deleted_at == None,
    ).first()
    if not transfer:
        raise HTTPException(status_code=404, detail="Transfer not found in this company context.")

    if transfer.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft transfers can be modified.")

    # Validate products in lines belong to tenant
    if payload.lines is not None:
        for line in payload.lines:
            product = db.query(Product).filter(
                Product.id == line.product_id,
                Product.tenant_id == tenant_id,
                Product.deleted_at == None,
            ).first()
            if not product:
                raise HTTPException(
                    status_code=400,
                    detail=f"Product with ID {line.product_id} not found in this company context.",
                )

    # Update header fields
    if payload.transfer_number is not None:
        transfer.transfer_number = payload.transfer_number
    if payload.transfer_date is not None:
        transfer.transfer_date = payload.transfer_date
    if payload.from_warehouse_id is not None:
        transfer.from_warehouse_id = payload.from_warehouse_id
    if payload.from_warehouse_name is not None:
        transfer.from_warehouse_name = payload.from_warehouse_name
    if payload.to_warehouse_id is not None:
        transfer.to_warehouse_id = payload.to_warehouse_id
    if payload.to_warehouse_name is not None:
        transfer.to_warehouse_name = payload.to_warehouse_name
    if payload.notes is not None:
        transfer.notes = payload.notes
    if payload.lines is not None:
        transfer.lines = [line.model_dump() for line in payload.lines]

    db.commit()
    db.refresh(transfer)
    return transfer


@router.post("/{id}/complete", response_model=TransferResponse)
def complete_transfer(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize")),
):
    """Complete a transfer: move stock from source warehouse to destination."""
    transfer = db.query(Transfer).filter(
        Transfer.id == id,
        Transfer.tenant_id == tenant_id,
        Transfer.deleted_at == None,
    ).first()
    if not transfer:
        raise HTTPException(status_code=404, detail="Transfer not found in this company context.")

    if transfer.status == "COMPLETED":
        raise HTTPException(status_code=400, detail="Transfer is already completed.")

    if transfer.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Cannot complete a cancelled transfer.")

    if not transfer.lines:
        raise HTTPException(status_code=400, detail="Transfer has no line items.")

    # Validate source warehouse has sufficient stock for each product
    for line_data in transfer.lines:
        product_id = uuid.UUID(line_data.get("product_id")) if isinstance(line_data.get("product_id"), str) else line_data.get("product_id")
        quantity = line_data.get("quantity", 0)

        product = db.query(Product).filter(
            Product.id == product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).with_for_update().first()
        if not product:
            raise HTTPException(
                status_code=400,
                detail=f"Product with ID {product_id} not found.",
            )

        current_stock = product.current_stock or 0
        if current_stock < quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient stock for product {product.name or product_id}. "
                       f"Available: {current_stock}, Required: {quantity}.",
            )

    # Deduct stock from source warehouse (deduct from product current_stock)
    for line_data in transfer.lines:
        product_id = uuid.UUID(line_data.get("product_id")) if isinstance(line_data.get("product_id"), str) else line_data.get("product_id")
        quantity = line_data.get("quantity", 0)

        product = db.query(Product).filter(
            Product.id == product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).with_for_update().first()
        if product:
            current_stock = product.current_stock or 0
            product.current_stock = current_stock - quantity

            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product_id,
                quantity=-quantity,
                balance_quantity=product.current_stock,
                reference_type="TRANSFER",
                reference_id=transfer.id,
            ))

    # Mark transfer as completed
    transfer.status = "COMPLETED"
    transfer.completed_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(transfer)
    return transfer


@router.post("/{id}/cancel", response_model=TransferResponse)
def cancel_transfer(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize")),
):
    """Cancel a draft or in-transit transfer."""
    transfer = db.query(Transfer).filter(
        Transfer.id == id,
        Transfer.tenant_id == tenant_id,
        Transfer.deleted_at == None,
    ).first()
    if not transfer:
        raise HTTPException(status_code=404, detail="Transfer not found in this company context.")

    if transfer.status == "COMPLETED":
        raise HTTPException(status_code=400, detail="Cannot cancel a completed transfer.")

    if transfer.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Transfer is already cancelled.")

    transfer.status = "CANCELLED"
    db.commit()
    db.refresh(transfer)
    return transfer
