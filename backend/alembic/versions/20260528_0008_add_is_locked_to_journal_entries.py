"""add is_locked column to journal_entries

Revision ID: 20260528_0008
Revises: 20260528_0007
Create Date: 2026-05-28
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0008"
down_revision: Union[str, Sequence[str], None] = "20260528_0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("journal_entries", sa.Column(
        "is_locked",
        sa.Boolean(),
        nullable=False,
        server_default="true",
    ))


def downgrade() -> None:
    op.drop_column("journal_entries", "is_locked")
