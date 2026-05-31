"""Add cancellation tracking columns and migrate draft records to auto-posted state.

Revision ID: 20260531_0001
Revises: 20260530_0001
Create Date: 2026-05-31
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "20260531_0001"
down_revision = "20260530_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── Add cancelled_at, cancelled_by to all financial document tables ──
    for table in ["invoices", "bills", "expenses", "credit_notes", "debit_notes"]:
        op.add_column(table, sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True))
        op.add_column(table, sa.Column("cancelled_by", sa.dialects.postgresql.UUID(), nullable=True))

    # ── Migrate existing DRAFT financial documents to POSTED ──
    # These were created before auto-posting; mark them as posted so the
    # system treats them as live accounting documents.
    op.execute("""
        UPDATE invoices SET status = 'POSTED'
        WHERE status = 'DRAFT' AND deleted_at IS NULL
    """)
    op.execute("""
        UPDATE bills SET status = 'POSTED'
        WHERE status = 'DRAFT' AND deleted_at IS NULL
    """)
    op.execute("""
        UPDATE expenses SET status = 'POSTED'
        WHERE status = 'DRAFT' AND deleted_at IS NULL
    """)
    op.execute("""
        UPDATE credit_notes SET status = 'POSTED'
        WHERE status = 'DRAFT' AND deleted_at IS NULL
    """)
    op.execute("""
        UPDATE debit_notes SET status = 'POSTED'
        WHERE status = 'DRAFT' AND deleted_at IS NULL
    """)


def downgrade() -> None:
    for table in ["invoices", "bills", "expenses", "credit_notes", "debit_notes"]:
        op.drop_column(table, "cancelled_by")
        op.drop_column(table, "cancelled_at")

    # Note: we don't revert POSTED → DRAFT since that would lose accounting state.
