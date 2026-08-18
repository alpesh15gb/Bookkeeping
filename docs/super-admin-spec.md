# Super Admin System — Specification

## Overview

A system-wide administrator role that can manage all tenants, subscriptions, expiry, and billing across the entire ApexBooks platform. This is separate from tenant-level roles (owner/admin/staff).

---

## 1. Data Model

### 1.1 Super Admin Role

```sql
-- Add to users table
ALTER TABLE users ADD COLUMN is_super_admin BOOLEAN DEFAULT FALSE;

-- Audit trail for admin actions
CREATE TABLE admin_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    target_tenant_id UUID,
    target_user_id UUID,
    details JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 1.2 Subscription Plans

```sql
CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,           -- 'free', 'starter', 'professional', 'enterprise'
    display_name VARCHAR(200) NOT NULL,
    description TEXT,
    price_monthly DECIMAL(10,2),          -- NULL = custom pricing
    price_yearly DECIMAL(10,2),           -- NULL = custom pricing
    currency VARCHAR(3) DEFAULT 'INR',
    
    -- Feature limits
    max_users INTEGER DEFAULT 1,
    max_invoices_per_month INTEGER,
    max_contacts INTEGER,
    max_products INTEGER,
    max_storage_mb INTEGER,
    
    -- Feature flags
    gst_filing BOOLEAN DEFAULT FALSE,
    e_invoicing BOOLEAN DEFAULT FALSE,
    bank_reconciliation BOOLEAN DEFAULT FALSE,
    inventory_management BOOLEAN DEFAULT FALSE,
    multi_branch BOOLEAN DEFAULT FALSE,
    api_access BOOLEAN DEFAULT FALSE,
    priority_support BOOLEAN DEFAULT FALSE,
    
    -- Trial settings
    trial_days INTEGER DEFAULT 14,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 1.3 Tenant Subscriptions

```sql
CREATE TABLE tenant_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES subscription_plans(id),
    
    -- Subscription details
    status VARCHAR(20) DEFAULT 'trialing',  -- 'trialing', 'active', 'past_due', 'cancelled', 'suspended'
    
    -- Billing period
    billing_cycle VARCHAR(20) DEFAULT 'monthly',  -- 'monthly', 'yearly', 'custom'
    
    -- Dates
    trial_start TIMESTAMPTZ,
    trial_end TIMESTAMPTZ,
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancelled_reason TEXT,
    
    -- Grace period
    grace_period_days INTEGER DEFAULT 7,
    grace_period_end TIMESTAMPTZ,
    
    -- Payment info (if using payment gateway)
    payment_method_id VARCHAR(200),
    last_payment_date TIMESTAMPTZ,
    next_payment_date TIMESTAMPTZ,
    
    -- Limits override (for enterprise custom plans)
    custom_limits JSONB,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(tenant_id)  -- One active subscription per tenant
);
```

### 1.4 Subscription History

```sql
CREATE TABLE subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    subscription_id UUID,
    action VARCHAR(50) NOT NULL,  -- 'created', 'upgraded', 'downgraded', 'renewed', 'cancelled', 'expired'
    old_plan_id UUID,
    new_plan_id UUID,
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    admin_id UUID,  -- NULL if system action
    reason TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 2. API Endpoints

### 2.1 Admin Authentication

```
POST /api/v1/admin/login          -- Super admin login (separate from tenant login)
POST /api/v1/admin/logout         -- Invalidate session
GET  /api/v1/admin/me             -- Current admin profile
```

### 2.2 Tenant Management

```
GET    /api/v1/admin/tenants              -- List all tenants (paginated, filterable)
GET    /api/v1/admin/tenants/:id          -- Tenant details with subscription
PUT    /api/v1/admin/tenants/:id          -- Update tenant (name, status, etc.)
POST   /api/v1/admin/tenants/:id/suspend  -- Suspend tenant
POST   /api/v1/admin/tenants/:id/activate -- Activate tenant
DELETE /api/v1/admin/tenants/:id          -- Soft delete tenant (with confirmation)
GET    /api/v1/admin/tenants/:id/usage    -- Usage stats (invoices, users, storage)
GET    /api/v1/admin/tenants/:id/activity -- Recent activity log
```

### 2.3 Subscription Management

```
GET    /api/v1/admin/plans                    -- List all plans
POST   /api/v1/admin/plans                    -- Create plan
PUT    /api/v1/admin/plans/:id                -- Update plan
DELETE /api/v1/admin/plans/:id                -- Deactivate plan

GET    /api/v1/admin/tenants/:id/subscription -- Get tenant's subscription
POST   /api/v1/admin/tenants/:id/subscription -- Create/update subscription
PUT    /api/v1/admin/tenants/:id/subscription -- Modify subscription
POST   /api/v1/admin/tenants/:id/subscription/extend   -- Extend trial/period
POST   /api/v1/admin/tenants/:id/subscription/cancel   -- Cancel subscription
POST   /api/v1/admin/tenants/:id/subscription/reactivate -- Reactivate
GET    /api/v1/admin/tenants/:id/subscription/history   -- Subscription history
```

### 2.4 Billing & Payments

```
GET    /api/v1/admin/billing/invoices         -- List all invoices
GET    /api/v1/admin/billing/invoices/:id     -- Invoice details
POST   /api/v1/admin/billing/invoices/:id/pay -- Record payment
POST   /api/v1/admin/billing/invoices/:id/refund -- Refund payment
GET    /api/v1/admin/billing/revenue          -- Revenue reports
GET    /api/v1/admin/billing/mrr              -- Monthly Recurring Revenue
```

### 2.5 System Dashboard

```
GET    /api/v1/admin/dashboard/overview       -- Total tenants, MRR, churn
GET    /api/v1/admin/dashboard/usage          -- Platform usage stats
GET    /api/v1/admin/dashboard/alerts         -- System alerts (expiry warnings, etc.)
GET    /api/v1/admin/dashboard/growth         -- Growth metrics
```

### 2.6 User Management (System-wide)

```
GET    /api/v1/admin/users                    -- List all users
GET    /api/v1/admin/users/:id                -- User details
PUT    /api/v1/admin/users/:id                -- Update user
POST   /api/v1/admin/users/:id/deactivate     -- Deactivate user
GET    /api/v1/admin/users/:id/tenants        -- All tenants user belongs to
```

---

## 3. Middleware & Guards

### 3.1 Super Admin Guard

```python
def require_super_admin(user: User = Depends(get_current_user)):
    if not user.is_super_admin:
        raise HTTPException(status_code=403, detail="Super admin access required")
    return user
```

### 3.2 Subscription Check Middleware

```python
def check_subscription_status(tenant_id: UUID, db: Session):
    """Check if tenant's subscription allows the requested action."""
    subscription = db.query(TenantSubscription).filter(
        TenantSubscription.tenant_id == tenant_id
    ).first()
    
    if not subscription:
        return  # No subscription = free tier
    
    # Check if trial/expired
    if subscription.status == 'trialing':
        if subscription.trial_end and subscription.trial_end < datetime.now(timezone.utc):
            # Trial expired → move to grace period or suspend
            if subscription.grace_period_end and subscription.grace_period_end < datetime.now(timezone.utc):
                subscription.status = 'suspended'
                db.commit()
                raise HTTPException(status_code=403, detail="Subscription expired. Please upgrade.")
    
    if subscription.status == 'suspended':
        raise HTTPException(status_code=403, detail="Account suspended. Contact support.")
    
    if subscription.status == 'cancelled':
        if subscription.current_period_end and subscription.current_period_end < datetime.now(timezone.utc):
            raise HTTPException(status_code=403, detail="Subscription ended. Please renew.")
```

### 3.3 Feature Gate

```python
def require_feature(feature_name: str):
    """Check if tenant's plan includes a specific feature."""
    def checker(tenant_id: UUID = Depends(get_tenant_id), db: Session = Depends(get_db_session)):
        subscription = db.query(TenantSubscription).filter(
            TenantSubscription.tenant_id == tenant_id
        ).first()
        
        if not subscription:
            raise HTTPException(status_code=403, detail=f"Feature '{feature_name}' requires a subscription")
        
        plan = subscription.plan
        if not getattr(plan, feature_name, False):
            raise HTTPException(status_code=403, detail=f"Feature '{feature_name}' not available in your plan")
        
        return True
    
    return Depends(checker)
```

---

## 4. Frontend Pages

### 4.1 Admin Dashboard (`/admin`)

- **Overview**: Total tenants, MRR, active trials, expiring soon
- **Revenue Chart**: MRR trend, churn rate
- **Recent Activity**: Latest admin actions
- **Alerts**: Expiring trials, failed payments, system issues

### 4.2 Tenants List (`/admin/tenants`)

- **Table**: Name, plan, status, users, invoices, MRR, expiry
- **Filters**: Status (active/trialing/suspended), plan, search
- **Bulk Actions**: Suspend, extend trial, export

### 4.3 Tenant Detail (`/admin/tenants/:id`)

- **Overview**: Company info, stats, usage
- **Subscription**: Current plan, dates, status, history
- **Users**: List of users, roles, last login
- **Activity**: Recent actions, invoices, payments
- **Actions**: Suspend, change plan, extend trial, reset

### 4.4 Plans Management (`/admin/plans`)

- **Plan Cards**: Name, price, features, tenant count
- **Create/Edit Plan**: Modal with all fields
- **Usage Stats**: How many tenants on each plan

### 4.5 Billing (`/admin/billing`)

- **Invoices**: All subscription invoices
- **Payments**: Payment history, refunds
- **Revenue**: MRR, ARR, churn, LTV

### 4.6 Users (`/admin/users`)

- **User List**: Email, name, tenants, last login, status
- **User Detail**: All tenants, activity, subscriptions

---

## 5. Business Logic

### 5.1 Trial Management

```python
def create_trial_subscription(tenant_id: UUID, plan_id: UUID, trial_days: int = 14):
    """Create a trial subscription for a new tenant."""
    subscription = TenantSubscription(
        tenant_id=tenant_id,
        plan_id=plan_id,
        status='trialing',
        trial_start=datetime.now(timezone.utc),
        trial_end=datetime.now(timezone.utc) + timedelta(days=trial_days),
        current_period_start=datetime.now(timezone.utc),
        current_period_end=datetime.now(timezone.utc) + timedelta(days=trial_days),
        grace_period_days=7,
    )
    db.add(subscription)
    db.commit()
```

### 5.2 Expiry Processing (Celery Beat)

```python
@celery_app.task
def process_subscription_expiry():
    """Run daily to check and process expired subscriptions."""
    now = datetime.now(timezone.utc)
    
    # 1. Trials expiring today → send reminder
    expiring_trials = db.query(TenantSubscription).filter(
        TenantSubscription.status == 'trialing',
        TenantSubscription.trial_end <= now + timedelta(days=1),
        TenantSubscription.trial_end > now,
    ).all()
    
    for sub in expiring_trials:
        send_trial_expiring_email(sub.tenant)
    
    # 2. Trials expired → move to grace period
    expired_trials = db.query(TenantSubscription).filter(
        TenantSubscription.status == 'trialing',
        TenantSubscription.trial_end <= now,
    ).all()
    
    for sub in expired_trials:
        sub.status = 'past_due'
        sub.grace_period_end = now + timedelta(days=sub.grace_period_days)
        sub.current_period_end = sub.grace_period_end
        db.commit()
    
    # 3. Grace period ended → suspend
    suspended = db.query(TenantSubscription).filter(
        TenantSubscription.status == 'past_due',
        TenantSubscription.grace_period_end <= now,
    ).all()
    
    for sub in suspended:
        sub.status = 'suspended'
        db.commit()
        send_account_suspended_email(sub.tenant)
```

### 5.3 Usage Enforcement

```python
def check_usage_limit(tenant_id: UUID, resource: str, db: Session):
    """Check if tenant has exceeded their plan's usage limit."""
    subscription = get_subscription(tenant_id, db)
    if not subscription:
        return  # Free tier
    
    plan = subscription.plan
    limits = subscription.custom_limits or {}
    
    # Get limit from custom or plan
    limit = limits.get(f'max_{resource}', getattr(plan, f'max_{resource}', None))
    if limit is None:
        return  # Unlimited
    
    # Get current usage
    usage = get_current_usage(tenant_id, resource, db)
    
    if usage >= limit:
        raise HTTPException(
            status_code=403,
            detail=f"Your plan allows {limit} {resource}. Please upgrade to continue."
        )
```

---

## 6. Security

### 6.1 Super Admin Auth

- Separate login flow (not tenant-scoped)
- IP whitelist optional
- 2FA mandatory for super admins
- Session timeout: 8 hours
- Audit all admin actions

### 6.2 Data Isolation

- Super admin queries bypass RLS (uses service role)
- All admin actions logged to admin_audit_log
- Cannot modify own super_admin flag
- Cannot delete last super admin

### 6.3 Rate Limiting

- Admin API: 100 requests/minute per IP
- Sensitive actions (suspend, delete): 10 requests/hour
- Bulk operations: 5 requests/hour

---

## 7. Migration Plan

### Phase 1: Core (Week 1)
- [ ] Database schema (plans, subscriptions, history)
- [ ] Super admin role and guard
- [ ] Basic CRUD for plans and subscriptions
- [ ] Admin API authentication

### Phase 2: Dashboard (Week 2)
- [ ] Admin dashboard page
- [ ] Tenant list and detail pages
- [ ] Plans management page
- [ ] Subscription management UI

### Phase 3: Billing (Week 3)
- [ ] Payment gateway integration (Razorpay/Stripe)
- [ ] Invoice generation
- [ ] Revenue reporting
- [ ] MRR/ARR calculations

### Phase 4: Automation (Week 4)
- [ ] Celery tasks for expiry processing
- [ ] Email notifications (trial expiring, payment failed, etc.)
- [ ] Webhook for subscription events
- [ ] Usage enforcement middleware

### Phase 5: Polish (Week 5)
- [ ] Bulk operations
- [ ] Export functionality
- [ ] Audit log viewer
- [ ] System health monitoring

---

## 8. Default Plans

| Plan | Price/mo | Users | Invoices/mo | GST | E-Invoice | Inventory |
|------|----------|-------|-------------|-----|-----------|-----------|
| Free | ₹0 | 1 | 50 | ❌ | ❌ | ❌ |
| Starter | ₹999 | 3 | 500 | ✅ | ❌ | ❌ |
| Professional | ₹2,999 | 10 | 2,000 | ✅ | ✅ | ✅ |
| Enterprise | Custom | Unlimited | Unlimited | ✅ | ✅ | ✅ |

---

## 9. Open Questions

1. **Payment Gateway**: Razorpay (India) or Stripe (global)?
2. **Invoice Generation**: Generate PDF invoices for subscriptions?
3. **Webhook Support**: Allow tenants to receive subscription events?
4. **Multi-Currency**: Support USD/EUR in addition to INR?
5. **Custom Enterprise Plans**: How to handle custom pricing?
6. **White-Label**: Allow resellers to brand the platform?
