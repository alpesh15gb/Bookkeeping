"""phase0 integrity updates

Revision ID: 20260524_0001
Revises: None
Create Date: 2026-05-24

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20260524_0001"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("tenant_settings", sa.Column("origin_state_code", sa.String(length=2), nullable=True))
    op.add_column("invoices", sa.Column("e_invoice_error", sa.Text(), nullable=True))
    op.create_unique_constraint("uq_eway_bill_number", "eway_bills", ["eway_bill_number"])
    op.create_foreign_key(
        "fk_journal_lines_account_id_accounts",
        "journal_lines",
        "accounts",
        ["account_id"],
        ["id"],
        ondelete="RESTRICT",
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint("fk_journal_lines_account_id_accounts", "journal_lines", type_="foreignkey")
    op.drop_constraint("uq_eway_bill_number", "eway_bills", type_="unique")
    op.drop_column("invoices", "e_invoice_error")
    op.drop_column("tenant_settings", "origin_state_code")
