"""Inventory location helpers shared by stock-posting workflows."""
import uuid
from typing import Optional

from sqlalchemy.orm import Session
from sqlalchemy import func
from decimal import Decimal

from src.infrastructure.database.models import Branch, StockLedger, TenantSetting


def resolve_default_warehouse_id(db: Session, tenant_id: uuid.UUID) -> Optional[uuid.UUID]:
    """Return the configured active warehouse, falling back deterministically.

    Companies that do not use warehouses may legitimately receive ``None``;
    their global product balance remains authoritative.
    """
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    configured = (setting.extra_settings or {}).get("default_warehouse_id") if setting else None
    if configured:
        try:
            configured_id = uuid.UUID(str(configured))
        except (TypeError, ValueError):
            configured_id = None
        if configured_id:
            exists = db.query(Branch.id).filter(
                Branch.id == configured_id,
                Branch.tenant_id == tenant_id,
                Branch.is_active == True,
                Branch.deleted_at == None,
            ).scalar()
            if exists:
                return exists

    default_row = db.query(Branch.id).filter(
        Branch.tenant_id == tenant_id,
        Branch.is_active == True,
        Branch.deleted_at == None,
    ).order_by(Branch.created_at, Branch.id).first()
    return default_row[0] if default_row else None


def resolve_reversal_warehouse_id(
    db: Session,
    tenant_id: uuid.UUID,
    reference_type: str,
    reference_id: uuid.UUID,
    product_id: uuid.UUID,
) -> Optional[uuid.UUID]:
    """Keep a reversal in the same location as its original movement."""
    warehouse_row = db.query(StockLedger.warehouse_id).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == reference_type,
        StockLedger.reference_id == reference_id,
        StockLedger.product_id == product_id,
    ).order_by(StockLedger.created_at.desc()).first()
    warehouse_id = warehouse_row[0] if warehouse_row else None
    return warehouse_id or resolve_default_warehouse_id(db, tenant_id)


def get_warehouse_stock(
    db: Session,
    tenant_id: uuid.UUID,
    warehouse_id: Optional[uuid.UUID],
    product_id: uuid.UUID,
) -> Optional[Decimal]:
    """Return location stock, or ``None`` when warehouses are not configured."""
    if warehouse_id is None:
        return None
    return db.query(func.coalesce(func.sum(StockLedger.quantity), 0)).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.warehouse_id == warehouse_id,
        StockLedger.product_id == product_id,
    ).scalar()
