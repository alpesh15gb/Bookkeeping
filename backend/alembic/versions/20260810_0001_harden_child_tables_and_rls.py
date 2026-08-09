"""Explicit tenant ownership for child tables + RLS scope fixes.

Revision ID: 20260810_0001
Revises: 20260809_0001
Create Date: 2026-08-10

Why this exists
---------------
A foreign key from a child table (e.g. invoice_lines.invoice_id ->
invoices.id) provides NO Row-Level Security protection: RLS filters rows of
the child table itself, and the child had no tenant_id column, so any
connection that could see the parent id could read/insert/update/delete the
child rows regardless of tenant.

This migration gives every financial child table its own tenant_id,
backfills it from the parent, makes it NOT NULL, enables RLS + FORCE RLS, and
adds a database trigger that rejects any row whose tenant_id does not match
its parent's tenant_id.

It also:
  * makes the journal-balance validator SECURITY DEFINER so the constraint
    evaluates on real rows even when RLS is enforced
  * grants NULL-tenant visibility to the global tax_templates / payment_terms
    rows so shared GST presets remain readable by restricted app roles
  * removes RLS from tenant_memberships (deliberate: it is the cross-tenant
    access-control registry, queried by login before any tenant context exists)
  * creates the controlled tenant-enumeration function for scheduled tasks
  * moves the legacy startup-time Vyapar column/backfill DDL into Alembic
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect, text

from src.core.postgres_hardening import (
    _CHILD_TABLES,
    apply_postgres_hardening,
)

revision = "20260810_0001"
down_revision = "20260809_0001"
branch_labels = None
depends_on = None


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def _column_exists(table: str, column: str) -> bool:
    try:
        inspector = inspect(op.get_bind())
        return column in {c["name"] for c in inspector.get_columns(table)}
    except Exception:
        return False


def _table_exists(table: str) -> bool:
    try:
        inspector = inspect(op.get_bind())
        return table in inspector.get_table_names()
    except Exception:
        return False


def _ensure_vyapar_columns() -> None:
    """Legacy startup DDL (previously ensure_vyapar_import_columns) as a migration."""
    migrations = [
        ("expense_categories", "deleted_at", "ALTER TABLE expense_categories ADD COLUMN deleted_at TIMESTAMPTZ"),
        ("contacts", "opening_balance", "ALTER TABLE contacts ADD COLUMN opening_balance NUMERIC(15,4) NOT NULL DEFAULT 0"),
        ("contacts", "custom_fields", "ALTER TABLE contacts ADD COLUMN custom_fields JSONB NOT NULL DEFAULT '{}'"),
        ("products", "party_item_rates", "ALTER TABLE products ADD COLUMN party_item_rates JSONB NOT NULL DEFAULT '{}'"),
        ("invoices", "vyapar_custom_fields", "ALTER TABLE invoices ADD COLUMN vyapar_custom_fields JSONB NOT NULL DEFAULT '{}'"),
        ("bills", "vyapar_custom_fields", "ALTER TABLE bills ADD COLUMN vyapar_custom_fields JSONB NOT NULL DEFAULT '{}'"),
    ]
    for table, column, ddl in migrations:
        if not _table_exists(table):
            continue
        if not _column_exists(table, column):
            op.execute(ddl)

    # Backfill NULL line descriptions from product names (previously startup DDL).
    backfills = [
        (
            "proforma_invoice_lines",
            "UPDATE proforma_invoice_lines pil SET description = p.name FROM products p "
            "WHERE pil.product_id = p.id AND (pil.description IS NULL OR pil.description = '')",
        ),
        (
            "invoice_lines",
            "UPDATE invoice_lines il SET description = p.name FROM products p "
            "WHERE il.product_id = p.id AND (il.description IS NULL OR il.description = '')",
        ),
        (
            "bill_lines",
            "UPDATE bill_lines bl SET description = p.name FROM products p "
            "WHERE bl.product_id = p.id AND (bl.description IS NULL OR bl.description = '')",
        ),
    ]
    for table, ddl in backfills:
        if _table_exists(table):
            op.execute(ddl)


def _add_child_tenant_columns() -> None:
    """Add tenant_id to child tables, backfill from parent, NOT NULL + index."""
    for child, (parent, fk_column) in _CHILD_TABLES.items():
        if not _table_exists(child) or not _table_exists(parent):
            continue
        if not _column_exists(child, "tenant_id"):
            op.add_column(child, sa.Column("tenant_id", sa.UUID(), nullable=True))
        op.execute(
            text(
                f"UPDATE {child} AS c SET tenant_id = p.tenant_id "
                f"FROM {parent} AS p WHERE c.{fk_column} = p.id AND c.tenant_id IS NULL"
            )
        )
        op.execute(text(f"ALTER TABLE {child} ALTER COLUMN tenant_id SET NOT NULL"))
        op.execute(text(f"CREATE INDEX IF NOT EXISTS ix_{child}_tenant_id ON {child} (tenant_id)"))


def upgrade() -> None:
    connection = op.get_bind()

    _ensure_vyapar_columns()

    if _is_postgresql():
        _add_child_tenant_columns()
        # Idempotent hardening: child-table RLS + tenant-match triggers,
        # global-table policies, journal-balance SECURITY DEFINER, tenant
        # enumerator function, FORCE RLS on every tenant-owned table.
        apply_postgres_hardening(connection)
    else:
        # SQLite (dev/test): keep the column addition so models and schema
        # stay consistent, but skip PostgreSQL-specific hardening.
        _add_child_tenant_columns()


def downgrade() -> None:
    # Tenant isolation hardening is intentionally retained on downgrade;
    # removing RLS from a live database is unsafe.  Only the schema additions
    # are reversible.
    for child in _CHILD_TABLES:
        if _column_exists(child, "tenant_id"):
            op.drop_index(f"ix_{child}_tenant_id", table_name=child)
            op.drop_column(child, "tenant_id")
