"""
Inter-warehouse transfer endpoints.
Follows the same patterns as inventory_adjustments.py.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import Transfer, Product, StockLedger, Branch
from src.schemas.bill_schemas import (
    TransferCreate, TransferUpdate, TransferResponse,
    TransferListResponse, PaginatedTransferResponse,
)
from src.api.deps import enforce_permission

router = APIRouter(prefix="/transfers", tags=["Transfers"])


def _validate_transfer_date(db: Session, tenant_id: uuid.UUID, value: str) -> None:
    try:
        transfer_date = date.fromisoformat(value)
    except ValueError:
        raise HTTPException(status_code=422, detail="Transfer date must be a valid date in YYYY-MM-DD format.")
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, transfer_date)


@router.post("", response_model=TransferResponse, status_code=status.HTTP_201_CREATED)
def create_transfer(
    payload: TransferCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """Create a new inter-warehouse transfer in DRAFT status."""
    _validate_transfer_date(db, tenant_id, payload.transfer_date)
    if payload.from_warehouse_id == payload.to_warehouse_id:
        raise HTTPException(status_code=400, detail="Source and destination warehouses must be different.")
    warehouses = db.query(Branch).filter(
        Branch.tenant_id == tenant_id,
        Branch.id.in_([payload.from_warehouse_id, payload.to_warehouse_id]),
        Branch.is_active == True,
        Branch.deleted_at == None,
    ).all()
    if len(warehouses) != 2:
        raise HTTPException(status_code=400, detail="Select two active warehouses belonging to this company.")
    warehouse_map = {warehouse.id: warehouse for warehouse in warehouses}
    product_ids = [line.product_id for line in payload.lines]
    if len(product_ids) != len(set(product_ids)):
        raise HTTPException(status_code=400, detail="A product can appear only once in a transfer.")
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
        from_warehouse_name=warehouse_map[payload.from_warehouse_id].name,
        to_warehouse_id=payload.to_warehouse_id,
        to_warehouse_name=warehouse_map[payload.to_warehouse_id].name,
        status="DRAFT",
        lines=[line.model_dump(mode="json") for line in payload.lines],
        notes=payload.notes,
    )

    db.add(transfer)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Transfer number already exists.")
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
    _validate_transfer_date(db, tenant_id, payload.transfer_date or transfer.transfer_date)

    from_id = payload.from_warehouse_id or transfer.from_warehouse_id
    to_id = payload.to_warehouse_id or transfer.to_warehouse_id
    if from_id == to_id:
        raise HTTPException(status_code=400, detail="Source and destination warehouses must be different.")
    warehouses = db.query(Branch).filter(
        Branch.tenant_id == tenant_id,
        Branch.id.in_([from_id, to_id]),
        Branch.is_active == True,
        Branch.deleted_at == None,
    ).all()
    if len(warehouses) != 2:
        raise HTTPException(status_code=400, detail="Select two active warehouses belonging to this company.")
    warehouse_map = {warehouse.id: warehouse for warehouse in warehouses}

    # Validate products in lines belong to tenant
    if payload.lines is not None:
        product_ids = [line.product_id for line in payload.lines]
        if len(product_ids) != len(set(product_ids)):
            raise HTTPException(status_code=400, detail="A product can appear only once in a transfer.")
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
    transfer.from_warehouse_name = warehouse_map[from_id].name
    if payload.to_warehouse_id is not None:
        transfer.to_warehouse_id = payload.to_warehouse_id
    transfer.to_warehouse_name = warehouse_map[to_id].name
    if payload.notes is not None:
        transfer.notes = payload.notes
    if payload.lines is not None:
        transfer.lines = [line.model_dump(mode="json") for line in payload.lines]

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Transfer number already exists.")
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
    ).with_for_update().first()
    if not transfer:
        raise HTTPException(status_code=404, detail="Transfer not found in this company context.")

    if transfer.status == "COMPLETED":
        raise HTTPException(status_code=400, detail="Transfer is already completed.")

    if transfer.status == "CANCELLED":
        raise HTTPException(status_code=400, detail="Cannot complete a cancelled transfer.")

    if not transfer.lines:
        raise HTTPException(status_code=400, detail="Transfer has no line items.")
    _validate_transfer_date(db, tenant_id, transfer.transfer_date)

    source_warehouse = db.query(Branch).filter(
        Branch.id == transfer.from_warehouse_id,
        Branch.tenant_id == tenant_id,
        Branch.is_active == True,
        Branch.deleted_at == None,
    ).first()
    destination_warehouse = db.query(Branch).filter(
        Branch.id == transfer.to_warehouse_id,
        Branch.tenant_id == tenant_id,
        Branch.is_active == True,
        Branch.deleted_at == None,
    ).first()
    if not source_warehouse or not destination_warehouse:
        raise HTTPException(status_code=400, detail="Both warehouses must be active before completing the transfer.")

    # Validate source warehouse has sufficient stock for each product.
    source_balances = {}
    for line_data in transfer.lines:
        product_id = uuid.UUID(line_data.get("product_id")) if isinstance(line_data.get("product_id"), str) else line_data.get("product_id")
        quantity = Decimal(str(line_data.get("quantity", 0)))

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

        source_stock = db.query(func.coalesce(func.sum(StockLedger.quantity), 0)).filter(
            StockLedger.tenant_id == tenant_id,
            StockLedger.product_id == product_id,
            StockLedger.warehouse_id == transfer.from_warehouse_id,
        ).scalar()
        source_balances[product_id] = source_stock
        if source_stock < quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient stock for product {product.name or product_id}. "
                       f"Available in {source_warehouse.name}: {source_stock}, Required: {quantity}.",
            )

    # A transfer changes location, not the tenant's total stock. Record equal
    # and opposite warehouse movements without changing Product.current_stock.
    for line_data in transfer.lines:
        product_id = uuid.UUID(line_data.get("product_id")) if isinstance(line_data.get("product_id"), str) else line_data.get("product_id")
        quantity = Decimal(str(line_data.get("quantity", 0)))

        product = db.query(Product).filter(
            Product.id == product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).with_for_update().first()
        if product:
            source_after = source_balances[product_id] - quantity
            destination_before = db.query(func.coalesce(func.sum(StockLedger.quantity), 0)).filter(
                StockLedger.tenant_id == tenant_id,
                StockLedger.product_id == product_id,
                StockLedger.warehouse_id == transfer.to_warehouse_id,
            ).scalar()

            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product_id,
                warehouse_id=transfer.from_warehouse_id,
                quantity=-quantity,
                balance_quantity=source_after,
                reference_type="TRANSFER",
                reference_id=transfer.id,
                rate=product.purchase_price,
            ))
            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product_id,
                warehouse_id=transfer.to_warehouse_id,
                quantity=quantity,
                balance_quantity=destination_before + quantity,
                reference_type="TRANSFER",
                reference_id=transfer.id,
                rate=product.purchase_price,
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
