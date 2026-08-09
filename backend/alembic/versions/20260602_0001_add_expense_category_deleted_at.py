"""Add deleted_at to expense_categories and unique constraint to numbering_series.

Revision ID: 20260602_0001
Revises: 20260601_0002
Create Date: 2026-06-02
"""
from alembic import op
import sqlalchemy as sa

revision = "20260602_0001"
down_revision = "20260601_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("expense_categories", sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
    op.create_unique_constraint("uq_numbering_series_tenant_doctype", "numbering_series", ["tenant_id", "document_type"])


def downgrade() -> None:
    op.drop_constraint("uq_numbering_series_tenant_doctype", "numbering_series", type_="unique")
    op.drop_column("expense_categories", "deleted_at")
