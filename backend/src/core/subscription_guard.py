"""
Subscription Guard — checks tenant subscription status before allowing API actions.

Usage:
    from src.core.subscription_guard import require_active_subscription, require_feature

    @router.post("/invoices")
    async def create_invoice(..., _sub=Depends(require_active_subscription)):
        ...

    @router.post("/gst/gstr1/export")
    async def export_gstr1(..., _sub=Depends(require_feature("gst_filing"))):
        ...
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from sqlalchemy.orm import Session

from src.core.database import get_db_session
from src.infrastructure.database.models import TenantSubscription, SubscriptionPlan
from src.api.deps import get_tenant_id

logger = logging.getLogger(__name__)


def get_subscription(tenant_id, db: Session) -> Optional[TenantSubscription]:
    """Get the tenant's current subscription."""
    return db.query(TenantSubscription).filter(
        TenantSubscription.tenant_id == tenant_id
    ).first()


def require_active_subscription(
    tenant_id=Depends(get_tenant_id),
    db: Session = Depends(get_db_session),
):
    """
    Require an active (or trialing) subscription.
    Blocks suspended, cancelled (past period end), and past_due (past grace) tenants.
    """
    sub = get_subscription(tenant_id, db)
    if not sub:
        # No subscription record = free tier (allows basic usage)
        return None

    now = datetime.now(timezone.utc)

    if sub.status == "suspended":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account suspended. Please contact support to reactivate."
        )

    if sub.status == "cancelled":
        if sub.current_period_end and sub.current_period_end < now:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Subscription has expired. Please renew to continue."
            )
        # Cancelled but still in paid period — allow

    if sub.status == "past_due":
        if sub.grace_period_end and sub.grace_period_end < now:
            # Move to suspended
            sub.status = "suspended"
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Grace period expired. Account suspended."
            )
        # In grace period — allow with warning
        logger.warning("Tenant %s is past_due (grace until %s)", tenant_id, sub.grace_period_end)

    if sub.status == "trialing":
        if sub.trial_end and sub.trial_end < now:
            from datetime import timedelta
            # Trial expired → move to past_due
            sub.status = "past_due"
            grace_length = (sub.grace_period_end - sub.trial_end) if sub.grace_period_end else timedelta(days=sub.grace_period_days)
            sub.grace_period_end = now + grace_length
            sub.current_period_end = sub.grace_period_end
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Trial has expired. Please subscribe to continue."
            )

    return sub


def require_feature(feature_name: str):
    """
    Require a specific feature from the tenant's plan.
    Returns a dependency that checks the feature flag.

    Usage:
        @router.post("/gst/gstr1/export")
        async def export(..., _sub=Depends(require_feature("gst_filing"))):
            ...
    """
    def checker(
        tenant_id=Depends(get_tenant_id),
        db: Session = Depends(get_db_session),
    ):
        sub = get_subscription(tenant_id, db)
        if not sub:
            # No subscription = free tier, no premium features
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Feature '{feature_name}' requires a subscription plan."
            )

        # Check if plan has the feature
        plan = sub.plan
        if not plan:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Feature '{feature_name}' requires a valid plan."
            )

        # Check custom limits first, then plan defaults
        limits = sub.custom_limits or {}
        feature_value = limits.get(feature_name, getattr(plan, feature_name, False))

        if not feature_value:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Feature '{feature_name}' is not available in your current plan ({plan.display_name}). Please upgrade."
            )

        return sub

    return Depends(checker)


def check_usage_limit(resource: str, limit_attr: str = None):
    """
    Check if tenant has exceeded their plan's usage limit for a resource.

    Usage:
        @router.post("/invoices")
        async def create(..., _sub=Depends(check_usage_limit("invoices", "max_invoices_per_month"))):
            ...
    """
    limit_attr = limit_attr or f"max_{resource}"

    def checker(
        tenant_id=Depends(get_tenant_id),
        db: Session = Depends(get_db_session),
    ):
        sub = get_subscription(tenant_id, db)
        if not sub:
            return None  # Free tier

        plan = sub.plan
        if not plan:
            return None

        limits = sub.custom_limits or {}
        limit = limits.get(limit_attr, getattr(plan, limit_attr, None))
        if limit is None:
            return None  # Unlimited

        # Import here to avoid circular imports
        from src.infrastructure.database.models import Invoice
        usage = db.query(Invoice).filter(Invoice.tenant_id == tenant_id).count()

        if usage >= limit:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Your plan allows {limit} {resource}. You have used {usage}. Please upgrade to continue."
            )

        return sub

    return Depends(checker)
