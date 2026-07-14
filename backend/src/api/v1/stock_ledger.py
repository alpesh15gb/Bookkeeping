from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
import uuid
from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel

from src.core.database import get_db_session
from src.infrastructure.database.models import StockLedger, Product, Branch
from src.schemas import SchemaBase
from src.api.deps import enforce_permission

router = APIRouter(prefix="/stock-ledger", tags=["Stock Ledger"])


# ---------------------------------------------------------------------------
# Response / Request Schemas
# ---------------------------------------------------------------------------

class StockLedgerEntryResponse(SchemaBase):
    id: uuid.UUID
    product_id: uuid.UUID
    product_name: str = ""
    sku: str = ""
    warehouse_id: Optional[uuid.UUID] = None
    warehouse_name: Optional[str] = None
    quantity: Decimal
    balance_quantity: Decimal
    reference_type: str
    reference_id: Optional[uuid.UUID] = None
    rate: Optional[Decimal] = None
    created_at: datetime


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=List[StockLedgerEntryResponse])
def list_stock_ledger(
    product_id: Optional[uuid.UUID] = None,
    reference_type: Optional[str] = None,
    warehouse_id: Optional[uuid.UUID] = None,
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view")),
):
    offset = (page - 1) * limit
    q = db.query(StockLedger).options(
        joinedload(StockLedger.product)
    ).filter(
        StockLedger.tenant_id == tenant_id,
    )
    if product_id:
        q = q.filter(StockLedger.product_id == product_id)
    if reference_type:
        q = q.filter(StockLedger.reference_type == reference_type)
    if warehouse_id:
        q = q.filter(StockLedger.warehouse_id == warehouse_id)
    entries = q.order_by(StockLedger.created_at.desc()).offset(offset).limit(limit).all()

    warehouse_ids = {e.warehouse_id for e in entries if e.warehouse_id}
    warehouse_names = {
        row.id: row.name
        for row in db.query(Branch.id, Branch.name).filter(
            Branch.tenant_id == tenant_id,
            Branch.id.in_(warehouse_ids),
        ).all()
    } if warehouse_ids else {}

    return [
        StockLedgerEntryResponse(
            id=e.id,
            product_id=e.product_id,
            product_name=e.product.name if e.product else "",
            sku=e.product.sku if e.product and e.product.sku else "",
            warehouse_id=e.warehouse_id,
            warehouse_name=warehouse_names.get(e.warehouse_id),
            quantity=e.quantity,
            balance_quantity=e.balance_quantity,
            reference_type=e.reference_type,
            reference_id=e.reference_id,
            rate=e.rate,
            created_at=e.created_at,
        )
        for e in entries
    ]


@router.get("/{id}", response_model=StockLedgerEntryResponse)
def get_stock_ledger_entry(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view")),
):
    entry = db.query(StockLedger).options(
        joinedload(StockLedger.product)
    ).filter(
        StockLedger.id == id,
        StockLedger.tenant_id == tenant_id,
    ).first()
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Stock ledger entry not found.")

    return StockLedgerEntryResponse(
        id=entry.id,
        product_id=entry.product_id,
        product_name=entry.product.name if entry.product else "",
        sku=entry.product.sku if entry.product and entry.product.sku else "",
        warehouse_id=entry.warehouse_id,
        warehouse_name=db.query(Branch.name).filter(
            Branch.id == entry.warehouse_id,
            Branch.tenant_id == tenant_id,
        ).scalar() if entry.warehouse_id else None,
        quantity=entry.quantity,
        balance_quantity=entry.balance_quantity,
        reference_type=entry.reference_type,
        reference_id=entry.reference_id,
        rate=entry.rate,
        created_at=entry.created_at,
    )
