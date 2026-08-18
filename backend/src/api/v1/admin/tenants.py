"""
Admin Tenant Management endpoints.
View and manage all tenants across the platform.
"""
import uuid
import logging
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Invoice, Bill,
    TenantSubscription, SubscriptionPlan,
)
from src.api.v1.admin.auth import require_super_admin

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/tenants", tags=["Admin Tenants"])


# --- Schemas ---

class TenantListItem(BaseModel):
    id: str
    legal_name: str
    trade_name: Optional[str]
    gstin: Optional[str]
    tax_mode: Optional[str]
    user_count: int
    invoice_count: int
    subscription_status: Optional[str]
    plan_name: Optional[str]
    created_at: str


class TenantDetail(BaseModel):
    id: str
    legal_name: str
    trade_name: Optional[str]
    gstin: Optional[str]
    pan: Optional[str]
    tax_mode: Optional[str]
    created_at: str
    user_count: int
    invoice_count: int
    bill_count: int
    subscription: Optional[dict]


class TenantUpdateRequest(BaseModel):
    legal_name: Optional[str] = None
    trade_name: Optional[str] = None


class SuspendTenantRequest(BaseModel):
    reason: str = "No reason provided"


class PaginatedTenants(BaseModel):
    items: List[TenantListItem]
    total: int
    page: int
    page_size: int
    pages: int


# --- Endpoints ---

@router.get("", response_model=PaginatedTenants)
async def list_tenants(
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    status_filter: Optional[str] = None,  # active, trialing, suspended, cancelled
    plan: Optional[str] = None,
):
    """List all tenants with subscription info, paginated and filterable."""
    query = db.query(Tenant).filter(Tenant.deleted_at == None)

    # Search
    if search:
        search_term = f"%{search}%"
        query = query.filter(
            (Tenant.legal_name.ilike(search_term)) |
            (Tenant.trade_name.ilike(search_term)) |
            (Tenant.gstin.ilike(search_term))
        )

    total = query.count()
    tenants = query.order_by(desc(Tenant.created_at)).offset((page - 1) * page_size).limit(page_size).all()

    items = []
    for t in tenants:
        # Get subscription
        sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == t.id).first()
        plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == sub.plan_id).first() if sub else None

        # Filter by status
        if status_filter and (not sub or sub.status != status_filter):
            continue

        # Filter by plan
        if plan and plan.name != plan:
            continue

        # Counts
        user_count = db.query(TenantMembership).filter(
            TenantMembership.tenant_id == t.id,
            TenantMembership.is_active == True
        ).count()
        invoice_count = db.query(Invoice).filter(Invoice.tenant_id == t.id).count()

        items.append(TenantListItem(
            id=str(t.id),
            legal_name=t.legal_name,
            trade_name=t.trade_name,
            gstin=t.gstin,
            tax_mode=t.tax_mode,
            user_count=user_count,
            invoice_count=invoice_count,
            subscription_status=sub.status if sub else None,
            plan_name=plan.display_name if plan else None,
            created_at=t.created_at.isoformat() if t.created_at else None,
        ))

    return PaginatedTenants(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        pages=(total + page_size - 1) // page_size,
    )


@router.get("/{tenant_id}")
async def get_tenant(
    tenant_id: uuid.UUID,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Get detailed tenant info including subscription."""
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id, Tenant.deleted_at == None).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found.")

    # Subscription
    sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == tenant.id).first()
    plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == sub.plan_id).first() if sub else None

    # Counts
    user_count = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == tenant.id,
        TenantMembership.is_active == True
    ).count()
    invoice_count = db.query(Invoice).filter(Invoice.tenant_id == tenant.id).count()
    bill_count = db.query(Bill).filter(Bill.tenant_id == tenant.id).count()

    subscription = None
    if sub:
        subscription = {
            "id": str(sub.id),
            "plan": {
                "id": str(plan.id),
                "name": plan.name,
                "display_name": plan.display_name,
                "price_monthly": float(plan.price_monthly) if plan.price_monthly else None,
                "price_yearly": float(plan.price_yearly) if plan.price_yearly else None,
            } if plan else None,
            "status": sub.status,
            "billing_cycle": sub.billing_cycle,
            "trial_start": sub.trial_start.isoformat() if sub.trial_start else None,
            "trial_end": sub.trial_end.isoformat() if sub.trial_end else None,
            "current_period_end": sub.current_period_end.isoformat() if sub.current_period_end else None,
            "grace_period_end": sub.grace_period_end.isoformat() if sub.grace_period_end else None,
            "cancelled_at": sub.cancelled_at.isoformat() if sub.cancelled_at else None,
        }

    return TenantDetail(
        id=str(tenant.id),
        legal_name=tenant.legal_name,
        trade_name=tenant.trade_name,
        gstin=tenant.gstin,
        pan=tenant.pan,
        tax_mode=tenant.tax_mode,
        created_at=tenant.created_at.isoformat() if tenant.created_at else None,
        user_count=user_count,
        invoice_count=invoice_count,
        bill_count=bill_count,
        subscription=subscription,
    )


@router.put("/{tenant_id}")
async def update_tenant(
    tenant_id: uuid.UUID,
    payload: TenantUpdateRequest,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Update tenant details."""
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id, Tenant.deleted_at == None).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found.")

    if payload.legal_name is not None:
        tenant.legal_name = payload.legal_name
    if payload.trade_name is not None:
        tenant.trade_name = payload.trade_name

    db.commit()
    return {"detail": "Tenant updated."}
