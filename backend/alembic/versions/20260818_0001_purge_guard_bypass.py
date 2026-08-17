"""Re-apply ledger immutability hardening with the purge-tenant exception.

Revision ID: 20260818_0001_purge_guard_bypass
Revises: 20260817_0001_debit_note_contact
Create Date: 2026-08-18

The OTP-gated company purge (POST /api/v1/purge/verify) deletes a tenant's
full accounting history, which the append-only ledger guards
(apex_guard_*_delete) forbid for every other path. The guards now permit
DELETE only while the transaction-scoped GUC ``app.purge_tenant_id`` names
the exact tenant being purged (set by reset_company_to_signup_defaults).

apply_postgres_hardening is idempotent and CREATE OR REPLACE's the guard
functions, so re-running it here ships the new guard bodies to databases
where the guards were created by earlier migrations.
"""

from alembic import op
from src.core.postgres_hardening import apply_postgres_hardening

revision = "20260818_0001_purge_guard_bypass"
down_revision = "20260817_0001_debit_note_contact"
branch_labels = None
depends_on = None


def upgrade() -> None:
    apply_postgres_hardening(op.get_bind())


def downgrade() -> None:
    # Nothing to undo at the schema level: the guard bodies are idempotently
    # CREATE OR REPLACE'd, and reverting to the unconditional guards would
    # re-break the purge flow. Downgrade is intentionally a no-op.
    pass
