"""Add PostgreSQL Row-Level Security policies for multi-tenant isolation.

Revision ID: 20260609_0001
Revises: 20260608_0001
Create Date: 2026-06-09
"""
from alembic import op

revision = "20260609_0001"
down_revision = "20260608_0001"
branch_labels = None
depends_on = None

TENANT_SCOPED_TABLES = [
    "accounts",
    "invoices",
    "invoice_lines",
    "bills",
    "bill_lines",
    "payments",
    "payment_allocations",
    "bill_payment_allocations",
    "journal_entries",
    "journal_lines",
    "contacts",
    "products",
    "expenses",
    "expense_categories",
    "estimates",
    "estimate_lines",
    "credit_notes",
    "credit_note_lines",
    "debit_notes",
    "debit_note_lines",
    "purchase_returns",
    "purchase_return_lines",
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
    "proforma_invoice_lines",
    "idempotency_keys",
    "tenant_settings",
]


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def upgrade() -> None:
    if not _is_postgresql():
        return

    for table in TENANT_SCOPED_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;")
        op.execute(
            f"DROP POLICY IF EXISTS tenant_isolation ON {table};"
        )
        op.execute(
            f"CREATE POLICY tenant_isolation ON {table} "
            f"USING (tenant_id::text = current_setting('app.current_tenant_id', true)) "
            f"WITH CHECK (tenant_id::text = current_setting('app.current_tenant_id', true))"
        )


def downgrade() -> None:
    if not _is_postgresql():
        return

    for table in TENANT_SCOPED_TABLES:
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {table};")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY;")
