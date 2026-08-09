"""Add missing columns: invoice/bill GST fields + accounts.account_group.

Revision ID: 20260608_0001
Revises: 20260606_0003
Create Date: 2026-06-08
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "20260608_0001"
down_revision = "20260606_0003"
branch_labels = None
depends_on = None


def _column_exists(table: str, column: str) -> bool:
    conn = op.get_bind()
    inspector = inspect(conn)
    return column in {c["name"] for c in inspector.get_columns(table)}


def upgrade() -> None:
    # invoices
    if not _column_exists("invoices", "is_rcm"):
        op.add_column("invoices", sa.Column("is_rcm", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists("invoices", "is_gst_inclusive"):
        op.add_column("invoices", sa.Column("is_gst_inclusive", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists("invoices", "supply_type"):
        op.add_column("invoices", sa.Column("supply_type", sa.String(20), nullable=False, server_default="DOMESTIC"))

    # bills
    if not _column_exists("bills", "is_gst_inclusive"):
        op.add_column("bills", sa.Column("is_gst_inclusive", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    if not _column_exists("bills", "itc_eligible"):
        op.add_column("bills", sa.Column("itc_eligible", sa.Boolean(), nullable=False, server_default=sa.text("true")))

    # accounts
    if not _column_exists("accounts", "account_group"):
        op.add_column("accounts", sa.Column("account_group", sa.String(100), nullable=True))


def downgrade() -> None:
    op.drop_column("accounts", "account_group")
    op.drop_column("bills", "itc_eligible")
    op.drop_column("bills", "is_gst_inclusive")
    op.drop_column("invoices", "supply_type")
    op.drop_column("invoices", "is_gst_inclusive")
    op.drop_column("invoices", "is_rcm")
