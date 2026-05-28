"""add unique constraint on idempotency_keys

Revision ID: 20260528_0005
Revises: 20260528_0004
Create Date: 2026-05-28

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0005"
down_revision: Union[str, Sequence[str], None] = "20260528_0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    try:
        op.create_unique_constraint(
            "uq_idempotency_key_tenant_method_path",
            "idempotency_keys",
            ["idempotency_key", "tenant_id", "method", "path"]
        )
    except Exception:
        pass


def downgrade() -> None:
    try:
        op.drop_constraint(
            "uq_idempotency_key_tenant_method_path",
            "idempotency_keys",
            type_="unique"
        )
    except Exception:
        pass
