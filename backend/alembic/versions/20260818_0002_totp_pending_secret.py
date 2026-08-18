"""Add users.totp_pending_secret for safe 2FA rotation.

Revision ID: 20260818_0002_totp_pending_secret
Revises: 20260818_0001_purge_guard_bypass
Create Date: 2026-08-18

2FA enablement now stages the new secret in ``totp_pending_secret`` and only
promotes it to ``totp_secret`` on successful verification. This keeps an
active authenticator working until the new one is verified (rotation no
longer overwrites the live secret), and requires a current TOTP code before
an active secret can be rotated at all.
"""

import sqlalchemy as sa

from alembic import op

revision = "20260818_0002_totp_pending_secret"
down_revision = "20260818_0001_purge_guard_bypass"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("totp_pending_secret", sa.String(32), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "totp_pending_secret")
