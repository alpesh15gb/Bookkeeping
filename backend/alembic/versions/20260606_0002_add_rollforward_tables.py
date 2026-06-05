"""Add opening_balance_snapshots and inventory_carry_forwards tables for FY roll-forward.

Revision ID: 20260606_0002
Revises: 20260606_0001
Create Date: 2026-06-06
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "20260606_0002"
down_revision = "20260606_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Opening Balance Snapshots
    op.create_table(
        "opening_balance_snapshots",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), nullable=False),
        sa.Column("financial_year_id", UUID(as_uuid=True), nullable=False),
        sa.Column("account_id", UUID(as_uuid=True), sa.ForeignKey("accounts.id"), nullable=False),
        sa.Column("account_type", sa.String(50), nullable=False),
        sa.Column("account_name", sa.String(150), nullable=False),
        sa.Column("account_code", sa.String(50), nullable=False),
        sa.Column("closing_balance", sa.Numeric(15, 4), nullable=False, server_default="0"),
        sa.Column("direction", sa.String(6), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_ob_snapshots_tenant_fy", "opening_balance_snapshots", ["tenant_id", "financial_year_id"])
    op.create_index("ix_ob_snapshots_account", "opening_balance_snapshots", ["account_id"])

    # Inventory Carry Forwards
    op.create_table(
        "inventory_carry_forwards",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", UUID(as_uuid=True), nullable=False),
        sa.Column("financial_year_id", UUID(as_uuid=True), nullable=False),
        sa.Column("product_id", UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("product_name", sa.String(150), nullable=False),
        sa.Column("product_sku", sa.String(50)),
        sa.Column("closing_quantity", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("closing_value", sa.Numeric(15, 4), nullable=False, server_default="0"),
        sa.Column("unit_rate", sa.Numeric(15, 4), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_icf_tenant_fy", "inventory_carry_forwards", ["tenant_id", "financial_year_id"])
    op.create_index("ix_icf_product", "inventory_carry_forwards", ["product_id"])


def downgrade() -> None:
    op.drop_table("inventory_carry_forwards")
    op.drop_table("opening_balance_snapshots")
