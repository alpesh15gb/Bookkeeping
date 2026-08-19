"""super admin and subscriptions tables

Revision ID: 0004_super_admin_subscriptions
Revises: 20260818_0002_totp_pending_secret
Create Date: 2026-08-19

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB

# revision identifiers
revision = '2004_super_admin_subscriptions'
down_revision = '20260818_0002_totp_pending_secret'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add super_admin flag to users (idempotent — may already exist from manual psql)
    conn = op.get_bind()
    result = conn.execute(sa.text(
        "SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='is_super_admin'"
    )).fetchone()
    if not result:
        op.add_column('users', sa.Column('is_super_admin', sa.Boolean(), server_default='false', nullable=False))
    
    # Create subscription_plans table
    op.create_table(
        'subscription_plans',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('name', sa.String(100), nullable=False, unique=True),
        sa.Column('display_name', sa.String(200), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('price_monthly', sa.Numeric(10, 2), nullable=True),
        sa.Column('price_yearly', sa.Numeric(10, 2), nullable=True),
        sa.Column('currency', sa.String(3), server_default='INR', nullable=False),
        
        # Feature limits
        sa.Column('max_users', sa.Integer(), server_default='1', nullable=False),
        sa.Column('max_invoices_per_month', sa.Integer(), nullable=True),
        sa.Column('max_contacts', sa.Integer(), nullable=True),
        sa.Column('max_products', sa.Integer(), nullable=True),
        sa.Column('max_storage_mb', sa.Integer(), nullable=True),
        
        # Feature flags
        sa.Column('gst_filing', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('e_invoicing', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('bank_reconciliation', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('inventory_management', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('multi_branch', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('api_access', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('priority_support', sa.Boolean(), server_default='false', nullable=False),
        
        # Trial settings
        sa.Column('trial_days', sa.Integer(), server_default='14', nullable=False),
        
        # Status
        sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
        
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    
    # Create tenant_subscriptions table
    op.create_table(
        'tenant_subscriptions',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('tenant_id', UUID(as_uuid=True), sa.ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False, unique=True),
        sa.Column('plan_id', UUID(as_uuid=True), sa.ForeignKey('subscription_plans.id'), nullable=False),
        
        # Subscription details
        sa.Column('status', sa.String(20), server_default='trialing', nullable=False),
        
        # Billing period
        sa.Column('billing_cycle', sa.String(20), server_default='monthly', nullable=False),
        
        # Dates
        sa.Column('trial_start', sa.DateTime(timezone=True), nullable=True),
        sa.Column('trial_end', sa.DateTime(timezone=True), nullable=True),
        sa.Column('current_period_start', sa.DateTime(timezone=True), nullable=True),
        sa.Column('current_period_end', sa.DateTime(timezone=True), nullable=True),
        sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('cancelled_reason', sa.Text(), nullable=True),
        
        # Grace period
        sa.Column('grace_period_days', sa.Integer(), server_default='7', nullable=False),
        sa.Column('grace_period_end', sa.DateTime(timezone=True), nullable=True),
        
        # Payment info
        sa.Column('payment_method_id', sa.String(200), nullable=True),
        sa.Column('last_payment_date', sa.DateTime(timezone=True), nullable=True),
        sa.Column('next_payment_date', sa.DateTime(timezone=True), nullable=True),
        
        # Limits override
        sa.Column('custom_limits', JSONB(), nullable=True),
        
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    
    # Create subscription_history table
    op.create_table(
        'subscription_history',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('tenant_id', UUID(as_uuid=True), sa.ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False),
        sa.Column('subscription_id', UUID(as_uuid=True), sa.ForeignKey('tenant_subscriptions.id', ondelete='SET NULL'), nullable=True),
        sa.Column('action', sa.String(50), nullable=False),
        sa.Column('old_plan_id', UUID(as_uuid=True), nullable=True),
        sa.Column('new_plan_id', UUID(as_uuid=True), nullable=True),
        sa.Column('old_status', sa.String(20), nullable=True),
        sa.Column('new_status', sa.String(20), nullable=True),
        sa.Column('admin_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('reason', sa.Text(), nullable=True),
        sa.Column('metadata', JSONB(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    
    # Create admin_audit_log table
    op.create_table(
        'admin_audit_log',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('admin_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=False),
        sa.Column('action', sa.String(100), nullable=False),
        sa.Column('target_tenant_id', UUID(as_uuid=True), nullable=True),
        sa.Column('target_user_id', UUID(as_uuid=True), nullable=True),
        sa.Column('details', JSONB(), nullable=True),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    
    # Create indexes
    op.create_index('ix_tenant_subscriptions_tenant_id', 'tenant_subscriptions', ['tenant_id'])
    op.create_index('ix_tenant_subscriptions_status', 'tenant_subscriptions', ['status'])
    op.create_index('ix_subscription_history_tenant_id', 'subscription_history', ['tenant_id'])
    op.create_index('ix_admin_audit_log_admin_id', 'admin_audit_log', ['admin_id'])
    op.create_index('ix_admin_audit_log_target_tenant_id', 'admin_audit_log', ['target_tenant_id'])
    
    # Insert default plans
    op.execute("""
        INSERT INTO subscription_plans (name, display_name, description, price_monthly, price_yearly, max_users, max_invoices_per_month, gst_filing, e_invoicing, bank_reconciliation, inventory_management, trial_days, sort_order)
        VALUES 
            ('free', 'Free', 'For small businesses just getting started', 0, 0, 1, 50, false, false, false, false, 14, 1),
            ('starter', 'Starter', 'For growing businesses', 999, 9990, 3, 500, true, false, false, false, 14, 2),
            ('professional', 'Professional', 'For established businesses', 2999, 29990, 10, 2000, true, true, true, true, 14, 3),
            ('enterprise', 'Enterprise', 'For large organizations', NULL, NULL, NULL, NULL, true, true, true, true, 30, 4);
    """)


def downgrade() -> None:
    op.drop_table('admin_audit_log')
    op.drop_table('subscription_history')
    op.drop_table('tenant_subscriptions')
    op.drop_table('subscription_plans')
    op.drop_column('users', 'is_super_admin')
