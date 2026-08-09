"""Add tax_mode column to tenants table.

Revision ID: 20260606_0003
Revises: 20260606_0002
Create Date: 2026-06-06
"""
from alembic import op
import sqlalchemy as sa

revision = "20260606_0003"
down_revision = "20260606_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add tax_mode column with default NON_GST
    # Backfill: if gstin is set, assume GST_REGULAR
    op.add_column("tenants", sa.Column("tax_mode", sa.String(20), nullable=False, server_default="NON_GST"))

    # Backfill existing tenants that have a GSTIN
    op.execute(
        "UPDATE tenants SET tax_mode = 'GST_REGULAR' WHERE gstin IS NOT NULL AND gstin != ''"
    )


def downgrade() -> None:
    op.drop_column("tenants", "tax_mode")
