"""
Admin Dashboard endpoints.
Platform-wide statistics and alerts.
"""
import uuid
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, TenantSubscription, SubscriptionPlan,
    Invoice, Bill,
)
from src.api.v1.admin.auth import require_super_admin

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin/dashboard", tags=["Admin Dashboard"])


@router.get("/overview")
async def dashboard_overview(
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """Platform-wide overview stats."""
    now = datetime.now(timezone.utc)

    # Tenant stats
    total_tenants = db.query(Tenant).filter(Tenant.deleted_at == None).count()
    active_tenants = db.query(Tenant).filter(
        Tenant.deleted_at == None,
        Tenant.created_at > now - timedelta(days=30)
    ).count()

    # Subscription stats
    total_subscriptions = db.query(TenantSubscription).count()
    trialing = db.query(TenantSubscription).filter(TenantSubscription.status == "trialing").count()
    active_subs = db.query(TenantSubscription).filter(TenantSubscription.status == "active").count()
    past_due = db.query(TenantSubscription).filter(TenantSubscription.status == "past_due").count()
    cancelled = db.query(TenantSubscription).filter(TenantSubscription.status == "cancelled").count()
    suspended = db.query(TenantSubscription).filter(TenantSubscription.status == "suspended").count()

    # Expiring soon (next 7 days)
    expiring_soon = db.query(TenantSubscription).filter(
        TenantSubscription.status == "trialing",
        TenantSubscription.trial_end <= now + timedelta(days=7),
        TenantSubscription.trial_end > now,
    ).count()

    # Revenue (MRR from active subscriptions)
    mrr_query = db.query(func.sum(SubscriptionPlan.price_monthly)).join(
        TenantSubscription, TenantSubscription.plan_id == SubscriptionPlan.id
    ).filter(
        TenantSubscription.status.in_(["active", "trialing"]),
        SubscriptionPlan.price_monthly.isnot(None)
    ).scalar()
    mrr = float(mrr_query) if mrr_query else 0

    # User stats
    total_users = db.query(User).filter(User.deleted_at == None).count()
    super_admins = db.query(User).filter(User.is_super_admin == True, User.deleted_at == None).count()

    # Document stats
    total_invoices = db.query(Invoice).count()
    total_bills = db.query(Bill).count()

    return {
        "tenants": {
            "total": total_tenants,
            "new_last_30d": active_tenants,
        },
        "subscriptions": {
            "total": total_subscriptions,
            "trialing": trialing,
            "active": active_subs,
            "past_due": past_due,
            "cancelled": cancelled,
            "suspended": suspended,
            "expiring_soon_7d": expiring_soon,
        },
        "revenue": {
            "mrr": mrr,
            "arr": mrr * 12,
        },
        "users": {
            "total": total_users,
            "super_admins": super_admins,
        },
        "documents": {
            "invoices": total_invoices,
            "bills": total_bills,
        },
    }


@router.get("/alerts")
async def dashboard_alerts(
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
):
    """System alerts — things that need attention."""
    now = datetime.now(timezone.utc)
    alerts = []

    # Trials expiring today
    expiring_today = db.query(TenantSubscription).filter(
        TenantSubscription.status == "trialing",
        TenantSubscription.trial_end <= now,
    ).all()
    for sub in expiring_today:
        tenant = db.query(Tenant).filter(Tenant.id == sub.tenant_id).first()
        alerts.append({
            "type": "trial_expired",
            "severity": "warning",
            "message": f"Trial expired for {tenant.legal_name if tenant else 'Unknown'}",
            "tenant_id": str(sub.tenant_id),
            "created_at": now.isoformat(),
        })

    # Past due (grace period)
    past_due = db.query(TenantSubscription).filter(
        TenantSubscription.status == "past_due",
    ).all()
    for sub in past_due:
        tenant = db.query(Tenant).filter(Tenant.id == sub.tenant_id).first()
        alerts.append({
            "type": "past_due",
            "severity": "critical",
            "message": f"Payment overdue for {tenant.legal_name if tenant else 'Unknown'}",
            "tenant_id": str(sub.tenant_id),
            "grace_period_end": sub.grace_period_end.isoformat() if sub.grace_period_end else None,
        })

    # Suspended tenants
    suspended = db.query(TenantSubscription).filter(
        TenantSubscription.status == "suspended",
    ).all()
    for sub in suspended:
        tenant = db.query(Tenant).filter(Tenant.id == sub.tenant_id).first()
        alerts.append({
            "type": "suspended",
            "severity": "info",
            "message": f"{tenant.legal_name if tenant else 'Unknown'} is suspended",
            "tenant_id": str(sub.tenant_id),
        })

    return {"alerts": alerts}


@router.get("/growth")
async def dashboard_growth(
    admin: User = Depends(require_super_admin),
    db: Session = Depends(get_db_session),
    days: int = Query(30, ge=7, le=365),
):
    """Growth metrics over time."""
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)

    # New tenants per day
    tenant_growth = db.query(
        func.date(Tenant.created_at).label("date"),
        func.count(Tenant.id).label("count")
    ).filter(
        Tenant.created_at >= start,
        Tenant.deleted_at == None,
    ).group_by(func.date(Tenant.created_at)).order_by(func.date(Tenant.created_at)).all()

    # New subscriptions per day
    sub_growth = db.query(
        func.date(SubscriptionHistory.created_at).label("date"),
        func.count(SubscriptionHistory.id).label("count")
    ).filter(
        SubscriptionHistory.created_at >= start,
        SubscriptionHistory.action == "created",
    ).group_by(func.date(SubscriptionHistory.created_at)).order_by(func.date(SubscriptionHistory.created_at)).all()

    return {
        "tenant_growth": [{"date": str(r.date), "count": r.count} for r in tenant_growth],
        "subscription_growth": [{"date": str(r.date), "count": r.count} for r in sub_growth],
    }
