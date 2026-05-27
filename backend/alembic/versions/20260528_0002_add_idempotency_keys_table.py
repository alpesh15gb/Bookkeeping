"""add idempotency_keys table

Revision ID: 20260528_0002
Revises: 20260528_0001
Create Date: 2026-05-28

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0002"
down_revision: Union[str, Sequence[str], None] = "20260528_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    result = conn.execute(
        sa.text(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_name='idempotency_keys'"
        )
    ).fetchone()
    if not result:
        op.create_table(
            "idempotency_keys",
            sa.Column("id", sa.UUID(), nullable=False),
            sa.Column("idempotency_key", sa.String(255), nullable=False),
            sa.Column("tenant_id", sa.UUID(), nullable=False),
            sa.Column("method", sa.String(10), nullable=False),
            sa.Column("path", sa.String(500), nullable=False),
            sa.Column("is_processed", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_idempotency_created", "idempotency_keys", ["created_at"])


def downgrade() -> None:
    try:
        op.drop_index("ix_idempotency_created", table_name="idempotency_keys")
    except Exception:
        pass
    try:
        op.drop_table("idempotency_keys")
    except Exception:
        pass
