"""fix transfer_date column type: String(10) -> Date

Revision ID: 20260725_0002
Revises: 20260725_0001
Create Date: 2026-07-25 14:57:42

"""
from datetime import datetime, timezone
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
import uuid

revision: str = "20260725_0002"
down_revision: Union[str, None] = "20260725_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    dialect = bind.dialect.name

    if dialect == "sqlite":
        # SQLite uses type affinity — TEXT and DATE both store as text.
        # The ORM will handle the Date type correctly on read/write regardless.
        # Just issue a no-op to keep the migration chain consistent.
        with op.batch_alter_table("transfers") as batch_op:
            batch_op.alter_column(
                "transfer_date",
                existing_type=sa.String(10),
                type_=sa.Date(),
                existing_nullable=True,
            )
    else:
        # PostgreSQL needs an actual ALTER COLUMN TYPE.
        op.execute(
            "ALTER TABLE transfers ALTER COLUMN transfer_date TYPE DATE "
            "USING transfer_date::date"
        )


def downgrade() -> None:
    bind = op.get_bind()
    dialect = bind.dialect.name

    if dialect == "sqlite":
        with op.batch_alter_table("transfers") as batch_op:
            batch_op.alter_column(
                "transfer_date",
                existing_type=sa.Date(),
                type_=sa.String(10),
                existing_nullable=True,
            )
    else:
        op.execute(
            "ALTER TABLE transfers ALTER COLUMN transfer_date TYPE VARCHAR(10)"
        )
