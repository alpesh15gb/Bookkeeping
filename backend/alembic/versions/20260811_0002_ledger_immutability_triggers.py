"""PostgreSQL-level immutability for the accounting ledger and stock ledger.

Revision ID: 20260811_0002_ledger_immutability_triggers
Revises: 20260811_0001_harden_payment_allocations
Create Date: 2026-08-11

ORM listeners (models.py) prevent in-place ledger edits, but raw SQL can
bypass them.  This migration installs BEFORE triggers on journal_entries,
journal_lines and stock_ledger that enforce append-only semantics at the
database itself for every role:

* journal_entries — no change to tenant_id / entry_date / reference_number /
  description / source_type / source_id / lock state / attribution; only the
  reversal/correction linkage metadata (reversed_by, reversed_at,
  reversal_transaction_id, reverses_transaction_id,
  replacement_transaction_id, updated_at) may change.  NEVER deleted.
* journal_lines — never updated, never deleted.
* stock_ledger — never updated except reversal-linkage metadata; never
  deleted.

There is deliberately NO client-settable bypass (a GUC naming eligible
source types would let any role holding DELETE on the ledger tables destroy
accounting history with raw SQL).  Corrections and the financial-year reopen
create REVERSAL entries instead.  All trigger functions are SECURITY DEFINER
(owned by the migration role), so the enforcement holds regardless of the
calling role.
"""

from alembic import op

from src.core.postgres_hardening import apply_postgres_hardening

revision = "20260811_0002_ledger_immutability_triggers"
down_revision = "20260811_0001_harden_payment_allocations"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        # Idempotent: creates/replaces the guard functions and triggers.
        apply_postgres_hardening(bind)


def downgrade() -> None:
    """Remove the immutability triggers (functions stay; they are idempotent).

    Downgrading ledger protection is destructive by nature and should only be
    used to unblock an emergency migration; the ORM listeners remain active.
    """
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    for trigger, table in (
        ("ck_journal_entries_immutable", "journal_entries"),
        ("ck_journal_entries_no_delete", "journal_entries"),
        ("ck_journal_lines_immutable", "journal_lines"),
        ("ck_journal_lines_no_delete", "journal_lines"),
        ("ck_stock_ledger_immutable", "stock_ledger"),
        ("ck_stock_ledger_no_delete", "stock_ledger"),
    ):
        op.execute(f'DROP TRIGGER IF EXISTS "{trigger}" ON "{table}"')
