"""Add contacts.credit_balance for advance payment support.

Revision ID: 20260609_0002
Revises: 20260609_0001
Create Date: 2026-06-09
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "20260609_0002"
down_revision = "20260609_0001"
branch_labels = None
depends_on = None


def _column_exists(table: str, column: str) -> bool:
    conn = op.get_bind()
    inspector = inspect(conn)
    return column in {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    if not _column_exists("contacts", "credit_balance"):
        op.add_column(
            "contacts",
            sa.Column("credit_balance", sa.Numeric(15, 4), nullable=False, server_default=sa.text("0")),
        )


def downgrade() -> None:
    if _column_exists("contacts", "credit_balance"):
        op.drop_column("contacts", "credit_balance")
