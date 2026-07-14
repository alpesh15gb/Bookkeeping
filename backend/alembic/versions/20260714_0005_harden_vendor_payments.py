"""Harden vendor payment modes, status and cancellation audit.

Revision ID: 20260714_0005
Revises: 20260714_0004
"""
from alembic import op
import sqlalchemy as sa


revision = "20260714_0005"
down_revision = "20260714_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("bill_payments", sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("bill_payments", sa.Column("cancellation_reason", sa.Text(), nullable=True))
    if op.get_bind().dialect.name == "postgresql":
        op.drop_constraint("ck_bill_payments_payment_mode", "bill_payments", type_="check")
        op.create_check_constraint(
            "ck_bill_payments_payment_mode", "bill_payments",
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'CHEQUE', 'NEFT_RTGS', 'OTHER')",
        )
        op.create_check_constraint("ck_bill_payments_amount_positive", "bill_payments", "amount > 0")
        op.create_check_constraint("ck_bill_payments_status", "bill_payments", "status IN ('ACTIVE', 'CANCELLED')")


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.drop_constraint("ck_bill_payments_status", "bill_payments", type_="check")
        op.drop_constraint("ck_bill_payments_amount_positive", "bill_payments", type_="check")
        op.drop_constraint("ck_bill_payments_payment_mode", "bill_payments", type_="check")
        op.create_check_constraint(
            "ck_bill_payments_payment_mode", "bill_payments",
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'OTHER')",
        )
    op.drop_column("bill_payments", "cancellation_reason")
    op.drop_column("bill_payments", "cancelled_at")
