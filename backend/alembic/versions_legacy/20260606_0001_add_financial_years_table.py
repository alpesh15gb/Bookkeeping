"""add financial_years table with audit trail and is_current guard

Revision ID: 20260606_0001
Revises: 20260602_0001
Create Date: 2026-06-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260606_0001"
down_revision: Union[str, Sequence[str], None] = "20260602_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    result = conn.execute(
        sa.text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_name='financial_years'"
        )
    ).fetchone()
    if not result:
        op.create_table(
            "financial_years",
            sa.Column("id", sa.UUID(), nullable=False),
            sa.Column("tenant_id", sa.UUID(), nullable=False),
            sa.Column("name", sa.String(50), nullable=False),
            sa.Column("start_date", sa.Date(), nullable=False),
            sa.Column("end_date", sa.Date(), nullable=False),
            sa.Column("status", sa.String(20), nullable=False, server_default="CURRENT"),
            sa.Column("is_current", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("closed_at", sa.DateTime(timezone=True)),
            sa.Column("closed_by", sa.UUID()),
            sa.Column("reopened_at", sa.DateTime(timezone=True)),
            sa.Column("reopened_by", sa.UUID()),
            sa.Column("reopen_reason", sa.Text()),
            sa.Column("journal_entry_id", sa.UUID()),
            sa.Column("transaction_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
            sa.Column("created_by", sa.UUID()),
            sa.Column("switched_by", sa.UUID()),
            sa.Column("last_accessed_at", sa.DateTime(timezone=True)),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_financial_years_tenant", "financial_years", ["tenant_id"])
        op.create_unique_constraint(
            "uq_financial_years_tenant_name",
            "financial_years",
            ["tenant_id", "name"],
        )
        op.create_check_constraint(
            "ck_financial_years_status",
            "financial_years",
            "status IN ('CURRENT', 'READY_TO_CLOSE', 'LOCKED', 'ARCHIVED')",
        )
        # Partial unique index: only one FY can be current per tenant
        op.execute(
            sa.text(
                "CREATE UNIQUE INDEX uq_financial_years_tenant_current "
                "ON financial_years (tenant_id) "
                "WHERE is_current = true"
            )
        )

    # Add financial_year_audits table
    audit_result = conn.execute(
        sa.text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_name='financial_year_audits'"
        )
    ).fetchone()
    if not audit_result:
        op.create_table(
            "financial_year_audits",
            sa.Column("id", sa.UUID(), nullable=False),
            sa.Column("tenant_id", sa.UUID(), nullable=False),
            sa.Column("financial_year_id", sa.UUID(), nullable=False),
            sa.Column("action", sa.String(50), nullable=False),
            sa.Column("detail", sa.Text()),
            sa.Column("performed_by", sa.UUID()),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_fy_audits_tenant", "financial_year_audits", ["tenant_id"])
        op.create_index("ix_fy_audits_fy", "financial_year_audits", ["financial_year_id"])


def downgrade() -> None:
    try:
        op.drop_index("ix_fy_audits_fy", table_name="financial_year_audits")
    except Exception:
        pass
    try:
        op.drop_index("ix_fy_audits_tenant", table_name="financial_year_audits")
    except Exception:
        pass
    try:
        op.drop_table("financial_year_audits")
    except Exception:
        pass
    try:
        op.execute(sa.text("DROP INDEX IF EXISTS uq_financial_years_tenant_current"))
    except Exception:
        pass
    try:
        op.drop_constraint("ck_financial_years_status", "financial_years", type_="check")
    except Exception:
        pass
    try:
        op.drop_constraint("uq_financial_years_tenant_name", "financial_years", type_="unique")
    except Exception:
        pass
    try:
        op.drop_index("ix_financial_years_tenant", table_name="financial_years")
    except Exception:
        pass
    try:
        op.drop_table("financial_years")
    except Exception:
        pass
