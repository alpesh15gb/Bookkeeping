"""phase2 — add bill.round_off column and integrity constraints

Revision ID: 20260527_0001
Revises: 20260524_0002
Create Date: 2026-05-27

"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260527_0001"
down_revision: Union[str, Sequence[str], None] = "20260524_0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add round_off column to bills
    op.add_column("bills", sa.Column("round_off", sa.Numeric(15, 4), nullable=False, server_default=sa.text("0.0000")))

    # Check constraints for invoices
    op.create_check_constraint(
        "ck_invoices_total_balance",
        "invoices",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off - discount_total",
    )
    op.create_check_constraint(
        "ck_invoices_amount_paid",
        "invoices",
        "amount_paid <= total",
    )

    # Check constraints for bills
    op.create_check_constraint(
        "ck_bills_total_balance",
        "bills",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off - discount_total",
    )
    op.create_check_constraint(
        "ck_bills_amount_paid",
        "bills",
        "amount_paid <= total",
    )

    # Check constraints for credit_notes (no discount_total column)
    op.create_check_constraint(
        "ck_credit_notes_total_balance",
        "credit_notes",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off",
    )

    # Check constraints for debit_notes (no discount_total column)
    op.create_check_constraint(
        "ck_debit_notes_total_balance",
        "debit_notes",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off",
    )


def downgrade() -> None:
    op.drop_constraint("ck_debit_notes_total_balance", "debit_notes", type_="check")
    op.drop_constraint("ck_credit_notes_total_balance", "credit_notes", type_="check")
    op.drop_constraint("ck_bills_amount_paid", "bills", type_="check")
    op.drop_constraint("ck_bills_total_balance", "bills", type_="check")
    op.drop_constraint("ck_invoices_amount_paid", "invoices", type_="check")
    op.drop_constraint("ck_invoices_total_balance", "invoices", type_="check")
    op.drop_column("bills", "round_off")
