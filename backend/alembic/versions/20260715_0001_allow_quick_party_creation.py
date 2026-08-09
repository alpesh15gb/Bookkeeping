"""Allow parties without an address or state during transaction entry.

Revision ID: 20260715_0001
Revises: 20260714_0007
"""
from alembic import op
import sqlalchemy as sa


revision = "20260715_0001"
down_revision = "20260714_0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "contacts",
        "billing_address",
        existing_type=sa.JSON(),
        nullable=True,
    )
    op.alter_column(
        "contacts",
        "state_code",
        existing_type=sa.String(length=2),
        nullable=True,
    )


def downgrade() -> None:
    op.execute("UPDATE contacts SET billing_address = '{}' WHERE billing_address IS NULL")
    op.execute("UPDATE contacts SET state_code = '00' WHERE state_code IS NULL")
    op.alter_column(
        "contacts",
        "state_code",
        existing_type=sa.String(length=2),
        nullable=False,
    )
    op.alter_column(
        "contacts",
        "billing_address",
        existing_type=sa.JSON(),
        nullable=False,
    )
