"""Fix RLS policies for nullable tenant tables.

Revision ID: 20260622_0001
Revises: 20260615_0001
Create Date: 2026-06-22
"""
from alembic import op

revision = "20260622_0001"
down_revision = "20260615_0001"
branch_labels = None
depends_on = None


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def upgrade() -> None:
    if not _is_postgresql():
        return

    for table in ["audit_logs", "terms_templates"]:
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {table};")
        op.execute(
            f"CREATE POLICY tenant_isolation ON {table} "
            f"USING (tenant_id IS NULL OR tenant_id::text = current_setting('app.current_tenant_id', true)) "
            f"WITH CHECK (tenant_id IS NULL OR tenant_id::text = current_setting('app.current_tenant_id', true))"
        )


def downgrade() -> None:
    if not _is_postgresql():
        return

    for table in ["audit_logs", "terms_templates"]:
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {table};")
        op.execute(
            f"CREATE POLICY tenant_isolation ON {table} "
            f"USING (tenant_id::text = current_setting('app.current_tenant_id', true)) "
            f"WITH CHECK (tenant_id::text = current_setting('app.current_tenant_id', true))"
        )
