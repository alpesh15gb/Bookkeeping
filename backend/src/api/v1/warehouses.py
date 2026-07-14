from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
import uuid
from datetime import datetime, timezone
from pydantic import BaseModel
from typing import Optional as Opt

from src.core.database import get_db_session
from src.infrastructure.database.models import Branch, StockLedger
from src.schemas import SchemaBase
from src.api.deps import enforce_permission

router = APIRouter(prefix="/warehouses", tags=["Warehouses"])


# ---------------------------------------------------------------------------
# Response / Request Schemas
# ---------------------------------------------------------------------------

class WarehouseResponse(SchemaBase):
    id: uuid.UUID
    name: str
    gstin: Opt[str] = None
    address: dict = {}
    is_active: bool = True
    created_at: datetime
    updated_at: datetime


class WarehouseCreate(BaseModel):
    name: str
    gstin: Opt[str] = None
    address: dict = {}
    is_active: bool = True


class WarehouseUpdate(BaseModel):
    name: Opt[str] = None
    gstin: Opt[str] = None
    address: Opt[dict] = None
    is_active: Opt[bool] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("", response_model=List[WarehouseResponse])
def list_warehouses(
    search: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view")),
):
    offset = (page - 1) * limit
    q = db.query(Branch).filter(
        Branch.tenant_id == tenant_id,
        Branch.deleted_at == None,
    )
    if search:
        q = q.filter(Branch.name.ilike(f"%{search}%"))
    return q.order_by(Branch.name.asc()).offset(offset).limit(limit).all()


@router.get("/{id}", response_model=WarehouseResponse)
def get_warehouse(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:view")),
):
    branch = db.query(Branch).filter(
        Branch.id == id,
        Branch.tenant_id == tenant_id,
        Branch.deleted_at == None,
    ).first()
    if not branch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Warehouse not found.")
    return branch


@router.post("", response_model=WarehouseResponse, status_code=status.HTTP_201_CREATED)
def create_warehouse(
    payload: WarehouseCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust")),
):
    branch = Branch(
        tenant_id=tenant_id,
        name=payload.name,
        gstin=payload.gstin,
        address=payload.address,
        is_active=payload.is_active,
    )
    db.add(branch)
    db.commit()
    db.refresh(branch)
    return branch


@router.put("/{id}", response_model=WarehouseResponse)
def update_warehouse(
    id: uuid.UUID,
    payload: WarehouseUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust")),
):
    branch = db.query(Branch).filter(
        Branch.id == id,
        Branch.tenant_id == tenant_id,
        Branch.deleted_at == None,
    ).first()
    if not branch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Warehouse not found.")

    if payload.name is not None:
        branch.name = payload.name
    if payload.gstin is not None:
        branch.gstin = payload.gstin
    if payload.address is not None:
        branch.address = payload.address
    if payload.is_active is not None:
        if payload.is_active is False:
            has_stock = db.query(StockLedger.product_id).filter(
                StockLedger.tenant_id == tenant_id,
                StockLedger.warehouse_id == id,
            ).group_by(StockLedger.product_id).having(
                func.sum(StockLedger.quantity) != 0,
            ).first()
            if has_stock:
                raise HTTPException(
                    status_code=409,
                    detail="Transfer all stock out before marking this warehouse inactive.",
                )
        branch.is_active = payload.is_active

    db.commit()
    db.refresh(branch)
    return branch


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_warehouse(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("inventory:adjust")),
):
    branch = db.query(Branch).filter(
        Branch.id == id,
        Branch.tenant_id == tenant_id,
        Branch.deleted_at == None,
    ).first()
    if not branch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Warehouse not found.")

    has_movements = db.query(StockLedger.id).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.warehouse_id == id,
    ).first()
    if has_movements:
        raise HTTPException(
            status_code=409,
            detail="Warehouse has stock history and cannot be deleted. Mark it inactive instead.",
        )

    branch.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return None
