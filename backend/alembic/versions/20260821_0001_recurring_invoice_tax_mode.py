"""persist GST-inclusive rate mode on recurring invoice templates

Revision ID: 20260821_0001_recurring_invoice_tax_mode
Revises: 20260818_0004_super_admin_subscriptions
Create Date: 2026-08-21
"""
from alembic import op
import sqlalchemy as sa

revision = "20260821_0001_recurring_invoice_tax_mode"
down_revision = "20260818_0004_super_admin_subscriptions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "recurring_invoices",
        sa.Column(
            "is_gst_inclusive",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade() -> None:
    op.drop_column("recurring_invoices", "is_gst_inclusive")
