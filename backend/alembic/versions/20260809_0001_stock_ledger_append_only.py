"""Phase 1 Gate 1: StockLedger append-only attribution and reversal linkage.

Adds, non-destructively (all columns nullable):

* ``stock_ledger`` — created_by / source_channel (actor + channel attribution,
  stamped by the ORM before_insert from session-scoped server context) and
  movement-level reversal linkage:
  - reverses_movement_id  (reversal movement -> original movement)
  - reversal_movement_id  (original movement -> its reversal movement)
  - reversed_by / reversed_at (actor + timestamp on the original)

The append-only protection itself (before_update / before_delete ORM guards)
is enforced at the model layer, not by database triggers, so this migration
only needs the columns + self-referencing foreign keys.

No status changes, no data writes, no deletes. Existing rows are preserved
with NULL attribution (Phase 1 Gate 3 backfills what is determinable).

Revision ID: 20260809_0001
Revises: 20260808_0001
Create Date: 2026-08-09
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20260809_0001"
down_revision: Union[str, Sequence[str], None] = "20260808_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


UUID = sa.UUID(as_uuid=True)


def upgrade() -> None:
    with op.batch_alter_table("stock_ledger") as batch_op:
        batch_op.add_column(sa.Column("created_by", UUID, nullable=True))
        batch_op.add_column(sa.Column("source_channel", sa.String(20), nullable=True))
        batch_op.add_column(sa.Column(
            "reverses_movement_id", UUID,
            sa.ForeignKey("stock_ledger.id", name="fk_stock_ledger_reverses_movement"),
            nullable=True,
        ))
        batch_op.add_column(sa.Column(
            "reversal_movement_id", UUID,
            sa.ForeignKey("stock_ledger.id", name="fk_stock_ledger_reversal_movement"),
            nullable=True,
        ))
        batch_op.add_column(sa.Column("reversed_by", UUID, nullable=True))
        batch_op.add_column(sa.Column("reversed_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("stock_ledger") as batch_op:
        batch_op.drop_column("reversed_at")
        batch_op.drop_column("reversed_by")
        batch_op.drop_column("reversal_movement_id")
        batch_op.drop_column("reverses_movement_id")
        batch_op.drop_column("source_channel")
        batch_op.drop_column("created_by")
