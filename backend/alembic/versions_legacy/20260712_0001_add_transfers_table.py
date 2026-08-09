"""Add transfers table for inter-warehouse transfers.

Revision ID: 20260712_0001
Revises: 20260622_0001
Create Date: 2026-07-12
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from sqlalchemy import inspect

revision = "20260712_0001"
down_revision = "20260622_0001"
branch_labels = None
depends_on = None


def _table_exists(table: str) -> bool:
    conn = op.get_bind()
    inspector = inspect(conn)
    return table in inspector.get_table_names()


def upgrade() -> None:
    if _table_exists("transfers"):
        return

    op.create_table(
        "transfers",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("transfer_number", sa.String(50), nullable=True),
        sa.Column("transfer_date", sa.String(10), nullable=True),
        sa.Column("from_warehouse_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("from_warehouse_name", sa.String(200), nullable=True),
        sa.Column("to_warehouse_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("to_warehouse_name", sa.String(200), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="DRAFT"),
        sa.Column("lines", sa.JSON, nullable=False, server_default="[]"),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('DRAFT', 'IN_TRANSIT', 'COMPLETED', 'CANCELLED')",
            name="ck_transfers_status",
        ),
    )
    op.create_index("ix_transfers_tenant_date", "transfers", ["tenant_id", "transfer_date"])
    op.create_index("ix_transfers_tenant_status", "transfers", ["tenant_id", "status"])
    op.create_index("ix_transfers_tenant_deleted", "transfers", ["tenant_id", "deleted_at"])


def downgrade() -> None:
    op.drop_table("transfers")
