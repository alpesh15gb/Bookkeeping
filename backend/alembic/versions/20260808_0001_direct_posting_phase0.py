"""Direct-posting Phase 0: audit metadata and reversal/replacement linkage.

Adds, non-destructively (all columns nullable):

* ``journal_entries``  — created_by / posted_by / posted_at / source_channel /
  reversed_by / reversed_at and the bidirectional self-referencing reversal
  (reversal_transaction_id / reverses_transaction_id) and correction
  (replacement_transaction_id / original_transaction_id) links.
* Ledger documents (invoices, bills, expenses, credit_notes, debit_notes,
  sales_returns, purchase_returns) — created_by and replacement linkage
  (replaces_id / replaced_by_id).
* Payments (payments, bill_payments) — created_by.

No status/CHECK-constraint changes: existing Draft/Posted workflows remain
fully functional until the Phase 2 migration.

Revision ID: 20260808_0001
Revises: 20260807_0001
Create Date: 2026-08-08
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260808_0001"
down_revision: Union[str, Sequence[str], None] = "20260807_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


UUID = sa.UUID(as_uuid=True)


def _add_actor_linkage(batch_op) -> None:
    """created_by + replacement linkage shared by the five main ledger docs."""
    batch_op.add_column(sa.Column("created_by", UUID, nullable=True))
    batch_op.add_column(sa.Column("replaces_id", UUID, nullable=True))
    batch_op.add_column(sa.Column("replaced_by_id", UUID, nullable=True))


def upgrade() -> None:
    # ── journal_entries: actor / channel / reversal / correction linkage ──
    with op.batch_alter_table("journal_entries") as batch_op:
        batch_op.add_column(sa.Column("created_by", UUID, nullable=True))
        batch_op.add_column(sa.Column("posted_by", UUID, nullable=True))
        batch_op.add_column(sa.Column("posted_at", sa.DateTime(timezone=True), nullable=True))
        batch_op.add_column(sa.Column("source_channel", sa.String(20), nullable=True))
        batch_op.add_column(sa.Column("reversed_by", UUID, nullable=True))
        batch_op.add_column(sa.Column("reversed_at", sa.DateTime(timezone=True), nullable=True))
        batch_op.add_column(sa.Column(
            "reversal_transaction_id", UUID,
            sa.ForeignKey("journal_entries.id", name="fk_journal_entries_reversal_transaction"),
            nullable=True,
        ))
        batch_op.add_column(sa.Column(
            "reverses_transaction_id", UUID,
            sa.ForeignKey("journal_entries.id", name="fk_journal_entries_reverses_transaction"),
            nullable=True,
        ))
        batch_op.add_column(sa.Column(
            "replacement_transaction_id", UUID,
            sa.ForeignKey("journal_entries.id", name="fk_journal_entries_replacement_transaction"),
            nullable=True,
        ))
        batch_op.add_column(sa.Column(
            "original_transaction_id", UUID,
            sa.ForeignKey("journal_entries.id", name="fk_journal_entries_original_transaction"),
            nullable=True,
        ))

    # ── Ledger documents: actor + replacement linkage ──
    for table in (
        "invoices",
        "bills",
        "expenses",
        "credit_notes",
        "debit_notes",
        "sales_returns",
        "purchase_returns",
    ):
        with op.batch_alter_table(table) as batch_op:
            _add_actor_linkage(batch_op)

    # ── Payments: actor only ──
    for table in ("payments", "bill_payments"):
        with op.batch_alter_table(table) as batch_op:
            batch_op.add_column(sa.Column("created_by", UUID, nullable=True))


def downgrade() -> None:
    for table in ("payments", "bill_payments"):
        with op.batch_alter_table(table) as batch_op:
            batch_op.drop_column("created_by")

    for table in (
        "invoices",
        "bills",
        "expenses",
        "credit_notes",
        "debit_notes",
        "sales_returns",
        "purchase_returns",
    ):
        with op.batch_alter_table(table) as batch_op:
            batch_op.drop_column("replaced_by_id")
            batch_op.drop_column("replaces_id")
            batch_op.drop_column("created_by")

    with op.batch_alter_table("journal_entries") as batch_op:
        batch_op.drop_column("original_transaction_id")
        batch_op.drop_column("replacement_transaction_id")
        batch_op.drop_column("reverses_transaction_id")
        batch_op.drop_column("reversal_transaction_id")
        batch_op.drop_column("reversed_at")
        batch_op.drop_column("reversed_by")
        batch_op.drop_column("source_channel")
        batch_op.drop_column("posted_at")
        batch_op.drop_column("posted_by")
        batch_op.drop_column("created_by")
