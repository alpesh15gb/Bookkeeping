"""add expense.bank_account_id column

Revision ID: 20260528_0001
Revises: 20260527_0001
Create Date: 2026-05-28

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0001"
down_revision: Union[str, Sequence[str], None] = "20260527_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    result = conn.execute(
        sa.text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='expenses' AND column_name='bank_account_id'"
        )
    ).fetchone()
    if not result:
        op.add_column("expenses", sa.Column("bank_account_id", sa.UUID(), nullable=True))
        op.create_foreign_key(
            "fk_expenses_bank_account",
            "expenses", "accounts",
            ["bank_account_id"], ["id"],
        )


def downgrade() -> None:
    try:
        op.drop_constraint("fk_expenses_bank_account", "expenses", type_="foreignkey")
    except Exception:
        pass
    try:
        op.drop_column("expenses", "bank_account_id")
    except Exception:
        pass
