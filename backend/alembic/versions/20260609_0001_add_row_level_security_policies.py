"""Add PostgreSQL Row-Level Security policies for multi-tenant isolation.

Revision ID: 20260609_0001
Revises: 20260608_0001
Create Date: 2026-06-09
"""
from alembic import op
from sqlalchemy import inspect, text

revision = "20260609_0001"
down_revision = "20260608_0001"
branch_labels = None
depends_on = None

# Only tables that have a direct tenant_id column.
# Line-item tables (invoice_lines, bill_lines, journal_lines, etc.) are excluded
# because they inherit tenant isolation from their parent tables via FK joins.
TENANT_SCOPED_TABLES = [
    "accounts",
    "invoices",
    "bills",
    "payments",
    "payment_allocations",
    "bill_payment_allocations",
    "journal_entries",
    "contacts",
    "products",
    "expenses",
    "expense_categories",
    "estimates",
    "credit_notes",
    "debit_notes",
    "purchase_returns",
    "stock_ledgers",
    "accounting_periods",
    "financial_years",
    "financial_year_audits",
    "bank_reconciliations",
    "gst_filings",
    "numbering_series",
    "fy_opening_balances",
    "accounting_opening_balances",
    "reminders",
    "gstr2a_entries",
    "einvoice_logs",
    "eway_bills",
    "audit_logs",
    "tenant_documents",
    "period_lock_audits",
    "proforma_invoices",
    "idempotency_keys",
    "tenant_settings",
]


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def _column_exists(table: str, column: str) -> bool:
    try:
        conn = op.get_bind()
        inspector = inspect(conn)
        return column in {c["name"] for c in inspector.get_columns(table)}
    except Exception:
        return False


def upgrade() -> None:
    if not _is_postgresql():
        return

    for table in TENANT_SCOPED_TABLES:
        if not _column_exists(table, "tenant_id"):
            continue
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;")
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {table};")
        op.execute(
            f"CREATE POLICY tenant_isolation ON {table} "
            f"USING (tenant_id::text = current_setting('app.current_tenant_id', true)) "
            f"WITH CHECK (tenant_id::text = current_setting('app.current_tenant_id', true))"
        )


def downgrade() -> None:
    if not _is_postgresql():
        return

    for table in TENANT_SCOPED_TABLES:
        if not _column_exists(table, "tenant_id"):
            continue
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {table};")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY;")
