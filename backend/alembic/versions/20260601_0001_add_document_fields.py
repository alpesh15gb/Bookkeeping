"""Add missing document fields: notes, terms, reference, sales_person.

Revision ID: 20260601_0001
Revises: 20260531_0001
Create Date: 2026-06-01
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "20260601_0001"
down_revision = "20260531_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── Add notes, terms_and_conditions, reference_number ──
    for table in ["invoices", "bills", "expenses"]:
        op.add_column(table, sa.Column("notes", sa.Text(), nullable=True))
        op.add_column(table, sa.Column("terms_and_conditions", sa.Text(), nullable=True))
        op.add_column(table, sa.Column("reference_number", sa.String(100), nullable=True))

    # ── Add sales_person_id to invoices ──
    op.add_column("invoices", sa.Column("sales_person_id", sa.dialects.postgresql.UUID(), nullable=True))


def downgrade() -> None:
    op.drop_column("invoices", "sales_person_id")

    for table in ["invoices", "bills", "expenses"]:
        op.drop_column(table, "reference_number")
        op.drop_column(table, "terms_and_conditions")
        op.drop_column(table, "notes")
