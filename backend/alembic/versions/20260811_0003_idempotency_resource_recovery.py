"""Idempotency committed-replay resource recovery.

Revision ID: 20260811_0003_idempotency_resource_recovery
Revises: 20260811_0002_ledger_immutability_triggers
Create Date: 2026-08-11

When a financial transaction commits but the API process dies before storing
the response, a retry with the same Idempotency-Key must not re-execute (the
COMMITTED marker is written atomically with the business commit — see
src/core/idempotency.py).  Without a stored response the middleware could
only return a generic replay message.  This migration adds resource_type /
resource_id columns so the atomic COMMITTED marker can capture the created
entity's identity and the retry can return the original resource id.
"""

import sqlalchemy as sa
from alembic import op

revision = "20260811_0003_idempotency_resource_recovery"
down_revision = "20260811_0002_ledger_immutability_triggers"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    columns = {c["name"] for c in sa.inspect(bind).get_columns("idempotency_keys")}
    if "resource_type" not in columns:
        op.add_column(
            "idempotency_keys",
            sa.Column("resource_type", sa.String(length=100), nullable=True),
        )
    if "resource_id" not in columns:
        op.add_column(
            "idempotency_keys",
            sa.Column("resource_id", sa.UUID(as_uuid=True), nullable=True),
        )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    columns = {c["name"] for c in sa.inspect(bind).get_columns("idempotency_keys")}
    if "resource_id" in columns:
        op.drop_column("idempotency_keys", "resource_id")
    if "resource_type" in columns:
        op.drop_column("idempotency_keys", "resource_type")
