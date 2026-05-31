"""Add TDS columns to bills table.

Revision ID: 20260601_0002
Revises: 20260601_0001
Create Date: 2026-06-01
"""
from alembic import op
import sqlalchemy as sa

revision = "20260601_0002"
down_revision = "20260601_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("bills", sa.Column("tds_rate", sa.Numeric(5, 2), nullable=False, server_default="0"))
    op.add_column("bills", sa.Column("tds_amount", sa.Numeric(15, 4), nullable=False, server_default="0"))


def downgrade() -> None:
    op.drop_column("bills", "tds_amount")
    op.drop_column("bills", "tds_rate")
