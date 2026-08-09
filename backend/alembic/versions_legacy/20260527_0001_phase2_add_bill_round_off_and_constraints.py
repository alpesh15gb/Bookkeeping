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


CONSTRAINTS = {
    "ck_invoices_total_balance": (
        "invoices",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off - discount_total",
    ),
    "ck_invoices_amount_paid": (
        "invoices",
        "amount_paid <= total",
    ),
    "ck_bills_total_balance": (
        "bills",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off - discount_total",
    ),
    "ck_bills_amount_paid": (
        "bills",
        "amount_paid <= total",
    ),
    "ck_credit_notes_total_balance": (
        "credit_notes",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off",
    ),
    "ck_debit_notes_total_balance": (
        "debit_notes",
        "total = subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off",
    ),
}


def upgrade() -> None:
    # Idempotent: add column only if it doesn't exist
    conn = op.get_bind()
    
    # Add round_off to bills if not present
    result = conn.execute(
        sa.text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='bills' AND column_name='round_off'"
        )
    ).fetchone()
    if not result:
        op.add_column("bills", sa.Column("round_off", sa.Numeric(15, 4), nullable=False, server_default=sa.text("0.0000")))

    # Create check constraints idempotently
    for name, (table, condition) in CONSTRAINTS.items():
        # Check if constraint already exists
        result = conn.execute(
            sa.text(
                "SELECT constraint_name FROM information_schema.table_constraints "
                "WHERE table_name=:t AND constraint_name=:n"
            ),
            {"t": table, "n": name},
        ).fetchone()
        if not result:
            op.create_check_constraint(name, table, condition)


def downgrade() -> None:
    for name in reversed(list(CONSTRAINTS.keys())):
        try:
            op.drop_constraint(name, CONSTRAINTS[name][0], type_="check")
        except Exception:
            pass
    try:
        op.drop_column("bills", "round_off")
    except Exception:
        pass
