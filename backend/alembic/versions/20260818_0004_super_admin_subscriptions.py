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


def _table_exists(conn, table_name: str) -> bool:
    result = conn.execute(sa.text(
        f"SELECT 1 FROM information_schema.tables WHERE table_name='{table_name}'"
    )).fetchone()
    return bool(result)


def _column_exists(conn, table_name: str, column_name: str) -> bool:
    result = conn.execute(sa.text(
        f"SELECT 1 FROM information_schema.columns WHERE table_name='{table_name}' AND column_name='{column_name}'"
    )).fetchone()
    return bool(result)


def upgrade() -> None:
    conn = op.get_bind()

    # ── users.is_super_admin ──────────────────────────────────────
    if not _column_exists(conn, 'users', 'is_super_admin'):
        op.add_column('users', sa.Column('is_super_admin', sa.Boolean(), server_default='false', nullable=False))

    # ── subscription_plans ────────────────────────────────────────
    if not _table_exists(conn, 'subscription_plans'):
        op.create_table(
            'subscription_plans',
            sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
            sa.Column('name', sa.String(100), nullable=False, unique=True),
            sa.Column('display_name', sa.String(200), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('price_monthly', sa.Numeric(10, 2), nullable=True),
            sa.Column('price_yearly', sa.Numeric(10, 2), nullable=True),
            sa.Column('currency', sa.String(3), server_default='INR', nullable=False),
            sa.Column('max_users', sa.Integer(), server_default='1', nullable=False),
            sa.Column('max_invoices_per_month', sa.Integer(), nullable=True),
            sa.Column('max_contacts', sa.Integer(), nullable=True),
            sa.Column('max_products', sa.Integer(), nullable=True),
            sa.Column('max_storage_mb', sa.Integer(), nullable=True),
            sa.Column('gst_filing', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('e_invoicing', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('bank_reconciliation', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('inventory_management', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('multi_branch', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('api_access', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('priority_support', sa.Boolean(), server_default='false', nullable=False),
            sa.Column('trial_days', sa.Integer(), server_default='14', nullable=False),
            sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
            sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        )

    # ── tenant_subscriptions ──────────────────────────────────────
    if not _table_exists(conn, 'tenant_subscriptions'):
        op.create_table(
            'tenant_subscriptions',
            sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
            sa.Column('tenant_id', UUID(as_uuid=True), sa.ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False, unique=True),
            sa.Column('plan_id', UUID(as_uuid=True), sa.ForeignKey('subscription_plans.id'), nullable=False),
            sa.Column('status', sa.String(20), server_default='trialing', nullable=False),
            sa.Column('billing_cycle', sa.String(20), server_default='monthly', nullable=False),
            sa.Column('trial_start', sa.DateTime(timezone=True), nullable=True),
            sa.Column('trial_end', sa.DateTime(timezone=True), nullable=True),
            sa.Column('current_period_start', sa.DateTime(timezone=True), nullable=True),
            sa.Column('current_period_end', sa.DateTime(timezone=True), nullable=True),
            sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('cancelled_reason', sa.Text(), nullable=True),
            sa.Column('grace_period_days', sa.Integer(), server_default='7', nullable=False),
            sa.Column('grace_period_end', sa.DateTime(timezone=True), nullable=True),
            sa.Column('payment_method_id', sa.String(200), nullable=True),
            sa.Column('last_payment_date', sa.DateTime(timezone=True), nullable=True),
            sa.Column('next_payment_date', sa.DateTime(timezone=True), nullable=True),
            sa.Column('custom_limits', JSONB(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        )

    # ── subscription_history ──────────────────────────────────────
    if not _table_exists(conn, 'subscription_history'):
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

    # ── admin_audit_log ───────────────────────────────────────────
    if not _table_exists(conn, 'admin_audit_log'):
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

    # ── Indexes (idempotent via IF NOT EXISTS) ────────────────────
    op.execute("CREATE INDEX IF NOT EXISTS ix_tenant_subscriptions_tenant_id ON tenant_subscriptions (tenant_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_tenant_subscriptions_status ON tenant_subscriptions (status)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_subscription_history_tenant_id ON subscription_history (tenant_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_admin_audit_log_admin_id ON admin_audit_log (admin_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_admin_audit_log_target_tenant_id ON admin_audit_log (target_tenant_id)")

    # ── Default plans (ON CONFLICT DO NOTHING) ────────────────────
    plan_count = conn.execute(sa.text("SELECT count(*) FROM subscription_plans")).scalar()
    if plan_count == 0:
        op.execute("""
            INSERT INTO subscription_plans (name, display_name, description, price_monthly, price_yearly, max_users, max_invoices_per_month, gst_filing, e_invoicing, bank_reconciliation, inventory_management, trial_days, sort_order)
            VALUES
                ('free', 'Free', 'For small businesses just getting started', 0, 0, 1, 50, false, false, false, false, 14, 1),
                ('starter', 'Starter', 'For growing businesses', 999, 9990, 3, 500, true, false, false, false, 14, 2),
                ('professional', 'Professional', 'For established businesses', 2999, 29990, 10, 2000, true, true, true, true, 14, 3),
                ('enterprise', 'Enterprise', 'For large organizations', NULL, NULL, 999, 99999, true, true, true, true, 30, 4);
        """)


def downgrade() -> None:
    op.drop_table('admin_audit_log')
    op.drop_table('subscription_history')
    op.drop_table('tenant_subscriptions')
    op.drop_table('subscription_plans')
    op.drop_column('users', 'is_super_admin')
