"""Preserve expense place of supply for deterministic GST edits.

Revision ID: 20260714_0004
Revises: 20260714_0003
"""
from alembic import op
import sqlalchemy as sa


revision = "20260714_0004"
down_revision = "20260714_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "expenses",
        sa.Column("place_of_supply_state_code", sa.String(length=2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("expenses", "place_of_supply_state_code")
