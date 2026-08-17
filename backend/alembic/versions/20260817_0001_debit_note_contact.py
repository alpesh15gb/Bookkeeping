"""Add contact_id to debit_notes for standalone debit notes.

Revision ID: 20260817_0001_debit_note_contact
Revises: 20260811_0004_least_privilege_grants
Create Date: 2026-08-17

Standalone debit notes (not linked to an invoice) previously could never be
finalized: the API accepted contact_id on creation but dropped it, and
finalization resolved the party from the invoice only.  This migration adds
the contact_id column (nullable, invoice-linked notes stay unchanged) and
indexes it for the list/detail queries.
"""

import sqlalchemy as sa
from alembic import op

revision = "20260817_0001_debit_note_contact"
down_revision = "20260811_0004_least_privilege_grants"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("debit_notes", sa.Column("contact_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=True))
    op.create_index("ix_debit_notes_contact_id", "debit_notes", ["contact_id"])
    op.create_foreign_key("fk_debit_notes_contact_id_contacts", "debit_notes", "contacts", ["contact_id"], ["id"])


def downgrade() -> None:
    op.drop_constraint("fk_debit_notes_contact_id_contacts", "debit_notes", type_="foreignkey")
    op.drop_index("ix_debit_notes_contact_id", table_name="debit_notes")
    op.drop_column("debit_notes", "contact_id")
