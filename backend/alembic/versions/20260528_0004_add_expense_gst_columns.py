"""add expense gst columns

Revision ID: 20260528_0004
Revises: 20260528_0003
Create Date: 2026-05-28

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0004"
down_revision: Union[str, Sequence[str], None] = "20260528_0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


COLUMNS = {
    "gst_rate": sa.Numeric(5, 2),
    "cgst_amount": sa.Numeric(15, 4),
    "sgst_amount": sa.Numeric(15, 4),
    "igst_amount": sa.Numeric(15, 4),
    "utgst_amount": sa.Numeric(15, 4),
    "cess_amount": sa.Numeric(15, 4),
    "round_off": sa.Numeric(15, 4),
}


def upgrade() -> None:
    conn = op.get_bind()
    for col_name, col_type in COLUMNS.items():
        result = conn.execute(
            sa.text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name='expenses' AND column_name=:col"
            ),
            {"col": col_name},
        ).fetchone()
        if not result:
            op.add_column(
                "expenses",
                sa.Column(col_name, col_type, nullable=False, server_default=sa.text("0")),
            )


def downgrade() -> None:
    for col_name in reversed(list(COLUMNS.keys())):
        try:
            op.drop_column("expenses", col_name)
        except Exception:
            pass
