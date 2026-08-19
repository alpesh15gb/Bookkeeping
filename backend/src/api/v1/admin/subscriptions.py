"""
Admin Subscription Management endpoints.
Manage plans, subscriptions, trials, and billing.
"""
import uuid
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    User, Tenant, TenantSubscription, SubscriptionPlan, SubscriptionHistory,
)
from src.api.v1.admin.auth import require_super_admin

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin", tags=["Admin Subscriptions"])


# --- Plan Schemas ---

class PlanCreateRequest(BaseModel):
    name: str
    display_name: str
    description: Optional[str] = None
    price_monthly: Optional[float] = None
    price_yearly: Optional[float] = None
    currency: str = "INR"
    max_users: int = 1
    max_invoices_per_month: Optional[int] = None
    max_contacts: Optional[int] = None
    max_products: Optional[int] = None
    gst_filing: bool = False
    e_invoicing: bool = False
    bank_reconciliation: bool = False
    inventory_management: bool = False
    multi_branch: bool = False
    api_access: bool = False
    priority_support: bool = False
    trial_days: int = 14


class PlanUpdateRequest(BaseModel):
    display_name: Optional[str] = None
    description: Optional[str] = None
    price_monthly: Optional[float] = None
    price_yearly: Optional[float] = None
    max_users: Optional[int] = None
    max_invoices_per_month: Optional[int] = None
    max_contacts: Optional[int] = None
    max_products: Optional[int] = None
    gst_filing: Optional[bool] = None
    e_invoicing: Optional[bool] = None
    bank_reconciliation: Optional[bool] = None
    inventory_management: Optional[bool] = None
    multi_branch: Optional[bool] = None
    api_access: Optional[bool] = None
    priority_support: Optional[bool] = None
    trial_days: Optional[int] = None
    is_active: Optional[bool] = None


class SubscriptionCreateRequest(BaseModel):
    plan_id: uuid.UUID
    billing_cycle: str = "monthly"


class ExtendSubscriptionRequest(BaseModel):
    days: int = 30
    reason: Optional[str] = None


class CancelSubscriptionRequest(BaseModel):
    reason: str = "No reason provided"
    cancel_immediately: bool = False


# --- Plan Endpoints ---

@router.get("/plans")
async def list_plans(
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
    include_inactive: bool = False,
):
    """List all subscription plans."""
    query = db.query(SubscriptionPlan)
    if not include_inactive:
        query = query.filter(SubscriptionPlan.is_active == True)

    plans = query.order_by(SubscriptionPlan.sort_order).all()

    result = []
    for plan in plans:
        # Count tenants on this plan
        tenant_count = db.query(TenantSubscription).filter(
            TenantSubscription.plan_id == plan.id,
            TenantSubscription.status.in_(["trialing", "active", "past_due"])
        ).count()

        result.append({
            "id": str(plan.id),
            "name": plan.name,
            "display_name": plan.display_name,
            "description": plan.description,
            "price_monthly": float(plan.price_monthly) if plan.price_monthly else None,
            "price_yearly": float(plan.price_yearly) if plan.price_yearly else None,
            "currency": plan.currency,
            "max_users": plan.max_users,
            "max_invoices_per_month": plan.max_invoices_per_month,
            "gst_filing": plan.gst_filing,
            "e_invoicing": plan.e_invoicing,
            "bank_reconciliation": plan.bank_reconciliation,
            "inventory_management": plan.inventory_management,
            "multi_branch": plan.multi_branch,
            "api_access": plan.api_access,
            "priority_support": plan.priority_support,
            "trial_days": plan.trial_days,
            "is_active": plan.is_active,
            "tenant_count": tenant_count,
            "sort_order": plan.sort_order,
        })

    return {"plans": result}


@router.post("/plans")
async def create_plan(
    payload: PlanCreateRequest,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Create a new subscription plan."""
    # Check name uniqueness
    existing = db.query(SubscriptionPlan).filter(SubscriptionPlan.name == payload.name).first()
    if existing:
        raise HTTPException(status_code=400, detail="Plan name already exists.")

    # Get max sort_order
    max_sort = db.query(func.max(SubscriptionPlan.sort_order)).scalar() or 0

    plan = SubscriptionPlan(
        name=payload.name,
        display_name=payload.display_name,
        description=payload.description,
        price_monthly=payload.price_monthly,
        price_yearly=payload.price_yearly,
        currency=payload.currency,
        max_users=payload.max_users,
        max_invoices_per_month=payload.max_invoices_per_month,
        max_contacts=payload.max_contacts,
        max_products=payload.max_products,
        gst_filing=payload.gst_filing,
        e_invoicing=payload.e_invoicing,
        bank_reconciliation=payload.bank_reconciliation,
        inventory_management=payload.inventory_management,
        multi_branch=payload.multi_branch,
        api_access=payload.api_access,
        priority_support=payload.priority_support,
        trial_days=payload.trial_days,
        sort_order=max_sort + 1,
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)

    return {"id": str(plan.id), "detail": "Plan created."}


@router.put("/plans/{plan_id}")
async def update_plan(
    plan_id: uuid.UUID,
    payload: PlanUpdateRequest,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Update a subscription plan."""
    plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found.")

    update_data = payload.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(plan, key, value)

    db.commit()
    return {"detail": "Plan updated."}


# --- Tenant Subscription Endpoints ---

@router.get("/tenants/{tenant_id}/subscription")
async def get_tenant_subscription(
    tenant_id: uuid.UUID,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Get a tenant's subscription details."""
    sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == tenant_id).first()
    if not sub:
        return {"subscription": None}

    plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == sub.plan_id).first()

    # Get history
    history = db.query(SubscriptionHistory).filter(
        SubscriptionHistory.tenant_id == tenant_id
    ).order_by(desc(SubscriptionHistory.created_at)).limit(20).all()

    return {
        "subscription": {
            "id": str(sub.id),
            "plan": {
                "id": str(plan.id),
                "name": plan.name,
                "display_name": plan.display_name,
                "price_monthly": float(plan.price_monthly) if plan.price_monthly else None,
            } if plan else None,
            "status": sub.status,
            "billing_cycle": sub.billing_cycle,
            "trial_start": sub.trial_start.isoformat() if sub.trial_start else None,
            "trial_end": sub.trial_end.isoformat() if sub.trial_end else None,
            "current_period_start": sub.current_period_start.isoformat() if sub.current_period_start else None,
            "current_period_end": sub.current_period_end.isoformat() if sub.current_period_end else None,
            "grace_period_end": sub.grace_period_end.isoformat() if sub.grace_period_end else None,
            "cancelled_at": sub.cancelled_at.isoformat() if sub.cancelled_at else None,
            "cancelled_reason": sub.cancelled_reason,
            "custom_limits": sub.custom_limits,
        },
        "history": [
            {
                "id": str(h.id),
                "action": h.action,
                "old_status": h.old_status,
                "new_status": h.new_status,
                "reason": h.reason,
                "created_at": h.created_at.isoformat() if h.created_at else None,
            }
            for h in history
        ],
    }


@router.post("/tenants/{tenant_id}/subscription")
async def create_or_update_subscription(
    tenant_id: uuid.UUID,
    payload: SubscriptionCreateRequest,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Create or update a tenant's subscription."""
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id, Tenant.deleted_at == None).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant not found.")

    plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.id == payload.plan_id).first()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan not found.")

    sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == tenant_id).first()
    now = datetime.now(timezone.utc)
    old_plan_id = None
    old_status = None

    if sub:
        # Update existing
        old_plan_id = sub.plan_id
        old_status = sub.status
        sub.plan_id = payload.plan_id
        sub.billing_cycle = payload.billing_cycle
        sub.status = "active"
        sub.current_period_start = now
        sub.current_period_end = now + timedelta(days=30 if payload.billing_cycle == "monthly" else 365)
        sub.cancelled_at = None
        sub.cancelled_reason = None
        sub.grace_period_end = None

        action = "upgraded" if payload.plan_id != old_plan_id else "renewed"
    else:
        # Create new
        sub = TenantSubscription(
            tenant_id=tenant_id,
            plan_id=payload.plan_id,
            billing_cycle=payload.billing_cycle,
            status="active",
            current_period_start=now,
            current_period_end=now + timedelta(days=30 if payload.billing_cycle == "monthly" else 365),
        )
        db.add(sub)
        action = "created"

    # Record history
    history = SubscriptionHistory(
        tenant_id=tenant_id,
        subscription_id=sub.id if sub else None,
        action=action,
        old_plan_id=old_plan_id if action == "upgraded" else None,
        new_plan_id=payload.plan_id,
        old_status=old_status,
        new_status="active",
        admin_id=admin.id,
        reason=f"Admin {action} subscription",
    )
    db.add(history)
    db.commit()

    return {"detail": f"Subscription {action}.", "status": "active"}


@router.post("/tenants/{tenant_id}/subscription/extend")
async def extend_subscription(
    tenant_id: uuid.UUID,
    payload: ExtendSubscriptionRequest,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Extend a tenant's subscription period."""
    sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == tenant_id).first()
    if not sub:
        raise HTTPException(status_code=404, detail="No subscription found for this tenant.")

    if sub.current_period_end:
        sub.current_period_end += timedelta(days=payload.days)
    if sub.trial_end and sub.status == "trialing":
        sub.trial_end += timedelta(days=payload.days)
    if sub.grace_period_end:
        sub.grace_period_end += timedelta(days=payload.days)

    # Record history
    history = SubscriptionHistory(
        tenant_id=tenant_id,
        subscription_id=sub.id,
        action="extended",
        old_status=sub.status,
        new_status=sub.status,
        admin_id=admin.id,
        reason=payload.reason or f"Extended by {payload.days} days",
        metadata_={"days_added": payload.days},
    )
    db.add(history)
    db.commit()

    return {"detail": f"Subscription extended by {payload.days} days."}


@router.post("/tenants/{tenant_id}/subscription/cancel")
async def cancel_subscription(
    tenant_id: uuid.UUID,
    payload: CancelSubscriptionRequest,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Cancel a tenant's subscription."""
    sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == tenant_id).first()
    if not sub:
        raise HTTPException(status_code=404, detail="No subscription found for this tenant.")

    old_status = sub.status
    now = datetime.now(timezone.utc)

    if payload.cancel_immediately:
        sub.status = "cancelled"
        sub.current_period_end = now
    else:
        # Cancel at end of current period
        sub.status = "cancelled"
        sub.cancelled_at = now

    sub.cancelled_reason = payload.reason

    # Record history
    history = SubscriptionHistory(
        tenant_id=tenant_id,
        subscription_id=sub.id,
        action="cancelled",
        old_status=old_status,
        new_status="cancelled",
        admin_id=admin.id,
        reason=payload.reason,
    )
    db.add(history)
    db.commit()

    return {"detail": "Subscription cancelled."}


@router.post("/tenants/{tenant_id}/subscription/reactivate")
async def reactivate_subscription(
    tenant_id: uuid.UUID,
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Reactivate a cancelled or suspended subscription."""
    sub = db.query(TenantSubscription).filter(TenantSubscription.tenant_id == tenant_id).first()
    if not sub:
        raise HTTPException(status_code=404, detail="No subscription found for this tenant.")

    old_status = sub.status
    now = datetime.now(timezone.utc)

    sub.status = "active"
    sub.current_period_start = now
    sub.current_period_end = now + timedelta(days=30)
    sub.cancelled_at = None
    sub.cancelled_reason = None
    sub.grace_period_end = None

    # Record history
    history = SubscriptionHistory(
        tenant_id=tenant_id,
        subscription_id=sub.id,
        action="reactivated",
        old_status=old_status,
        new_status="active",
        admin_id=admin.id,
        reason="Admin reactivated subscription",
    )
    db.add(history)
    db.commit()

    return {"detail": "Subscription reactivated."}
