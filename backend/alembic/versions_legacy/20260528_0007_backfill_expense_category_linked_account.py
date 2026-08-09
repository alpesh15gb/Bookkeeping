"""backfill expense_category linked_account_id

Revision ID: 20260528_0007
Revises: 20260528_0006
Create Date: 2026-05-28

Sets linked_account_id to the standard "purchases" account for any
expense_category that has a NULL linked_account_id.  The account ID
is deterministic (uuid5 DNS namespace) and matches the value that
AccountResolver creates on first use.
"""
from typing import Sequence, Union
import uuid
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0007"
down_revision: Union[str, Sequence[str], None] = "20260528_0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

PURCHASES_ACCOUNT_ID = uuid.uuid5(uuid.NAMESPACE_DNS, "account.purchases")


def upgrade() -> None:
    conn = op.get_bind()

    # Ensure the Purchases account exists for the default tenant
    tenant_row = conn.execute(
        sa.text("SELECT id FROM tenants LIMIT 1")
    ).fetchone()
    if tenant_row is None:
        return

    default_tenant_id = str(tenant_row[0])

    existing = conn.execute(
        sa.text("SELECT 1 FROM accounts WHERE id = :aid"),
        {"aid": str(PURCHASES_ACCOUNT_ID)},
    ).fetchone()

    if existing is None:
        conn.execute(
            sa.text(
                "INSERT INTO accounts (id, tenant_id, name, code, account_type, is_active, created_at, updated_at) "
                "VALUES (:id, :tid, 'Purchases', 'PUR', 'EXPENSE', TRUE, NOW(), NOW())"
            ),
            {"id": str(PURCHASES_ACCOUNT_ID), "tid": default_tenant_id},
        )

    conn.execute(
        sa.text(
            "UPDATE expense_categories SET linked_account_id = :aid WHERE linked_account_id IS NULL"
        ),
        {"aid": str(PURCHASES_ACCOUNT_ID)},
    )


def downgrade() -> None:
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "UPDATE expense_categories SET linked_account_id = NULL WHERE linked_account_id = :aid"
        ),
        {"aid": str(PURCHASES_ACCOUNT_ID)},
    )
