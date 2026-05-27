"""add accounting_periods table

Revision ID: 20260528_0003
Revises: 20260528_0002
Create Date: 2026-05-28

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0003"
down_revision: Union[str, Sequence[str], None] = "20260528_0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    result = conn.execute(
        sa.text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_name='accounting_periods'"
        )
    ).fetchone()
    if not result:
        op.create_table(
            "accounting_periods",
            sa.Column("id", sa.UUID(), nullable=False),
            sa.Column("tenant_id", sa.UUID(), nullable=False),
            sa.Column("period_name", sa.String(50), nullable=False),
            sa.Column("start_date", sa.Date(), nullable=False),
            sa.Column("end_date", sa.Date(), nullable=False),
            sa.Column("is_closed", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_accounting_periods_tenant", "accounting_periods", ["tenant_id"])
        op.create_unique_constraint(
            "uq_accounting_periods_tenant_name",
            "accounting_periods",
            ["tenant_id", "period_name"],
        )
        op.create_check_constraint(
            "ck_accounting_periods_is_closed",
            "accounting_periods",
            "is_closed IN (true, false)",
        )


def downgrade() -> None:
    try:
        op.drop_constraint("ck_accounting_periods_is_closed", "accounting_periods", type_="check")
    except Exception:
        pass
    try:
        op.drop_constraint("uq_accounting_periods_tenant_name", "accounting_periods", type_="unique")
    except Exception:
        pass
    try:
        op.drop_index("ix_accounting_periods_tenant", table_name="accounting_periods")
    except Exception:
        pass
    try:
        op.drop_table("accounting_periods")
    except Exception:
        pass
