"""Harden Level 1 accounting and financial-year invariants.

Revision ID: 20260714_0001
Revises: 20260712_0001
Create Date: 2026-07-14
"""
from alembic import op


revision = "20260714_0001"
down_revision = "20260712_0001"
branch_labels = None
depends_on = None


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def upgrade() -> None:
    # Production uses PostgreSQL. SQLite test databases receive the equivalent
    # portable constraints from SQLAlchemy metadata; SQLite cannot add named
    # constraints to existing tables without table recreation.
    if not _is_postgresql():
        return

    # These indexes close check-then-insert races in numbering, voucher posting,
    # and financial-year switching. Deployment intentionally fails if legacy
    # duplicates exist so they can be reconciled instead of silently discarded.
    op.create_unique_constraint(
        "uq_journal_entries_tenant_reference",
        "journal_entries",
        ["tenant_id", "reference_number"],
    )
    op.create_unique_constraint(
        "uq_journal_entries_tenant_source",
        "journal_entries",
        ["tenant_id", "source_type", "source_id"],
    )
    op.execute(
        "CREATE UNIQUE INDEX uq_numbering_series_active_document "
        "ON numbering_series (tenant_id, document_type) WHERE is_active"
    )
    op.create_check_constraint(
        "ck_numbering_series_next_number", "numbering_series", "next_number > 0"
    )
    op.create_check_constraint(
        "ck_numbering_series_padding", "numbering_series", "padding_digits BETWEEN 1 AND 12"
    )
    op.create_check_constraint(
        "ck_accounts_type",
        "accounts",
        "account_type IN ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE')",
    )
    op.create_check_constraint(
        "ck_accounting_periods_date_range", "accounting_periods", "start_date <= end_date"
    )
    op.create_check_constraint(
        "ck_financial_years_date_range", "financial_years", "start_date <= end_date"
    )

    op.execute(
        "CREATE UNIQUE INDEX uq_financial_years_one_current "
        "ON financial_years (tenant_id) WHERE is_current"
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION apex_validate_journal_balance()
        RETURNS trigger AS $$
        DECLARE
            target_entry uuid;
            line_count integer;
            debit_total numeric(19,4);
            credit_total numeric(19,4);
        BEGIN
            IF TG_TABLE_NAME = 'journal_entries' THEN
                target_entry := COALESCE(NEW.id, OLD.id);
            ELSE
                target_entry := COALESCE(NEW.entry_id, OLD.entry_id);
            END IF;

            IF NOT EXISTS (SELECT 1 FROM journal_entries WHERE id = target_entry) THEN
                RETURN NULL;
            END IF;

            SELECT count(*),
                   COALESCE(sum(amount) FILTER (WHERE direction = 'DEBIT'), 0),
                   COALESCE(sum(amount) FILTER (WHERE direction = 'CREDIT'), 0)
              INTO line_count, debit_total, credit_total
              FROM journal_lines
             WHERE entry_id = target_entry;

            IF line_count < 2 OR debit_total <> credit_total THEN
                RAISE EXCEPTION 'Journal entry % is not balanced (debits %, credits %, lines %)',
                    target_entry, debit_total, credit_total, line_count
                    USING ERRCODE = '23514';
            END IF;
            RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE CONSTRAINT TRIGGER ck_journal_entry_balanced
        AFTER INSERT OR UPDATE ON journal_entries
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION apex_validate_journal_balance();

        CREATE CONSTRAINT TRIGGER ck_journal_lines_balanced
        AFTER INSERT OR UPDATE OR DELETE ON journal_lines
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION apex_validate_journal_balance();
        """
    )
    op.execute(
        """
        CREATE OR REPLACE FUNCTION apex_prevent_audit_mutation()
        RETURNS trigger AS $$
        BEGIN
            RAISE EXCEPTION 'Audit log entries are immutable'
                USING ERRCODE = '55000';
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER audit_logs_immutable
        BEFORE UPDATE OR DELETE ON audit_logs
        FOR EACH ROW EXECUTE FUNCTION apex_prevent_audit_mutation();
        """
    )


def downgrade() -> None:
    if not _is_postgresql():
        return

    op.execute("DROP TRIGGER IF EXISTS ck_journal_lines_balanced ON journal_lines")
    op.execute("DROP TRIGGER IF EXISTS ck_journal_entry_balanced ON journal_entries")
    op.execute("DROP FUNCTION IF EXISTS apex_validate_journal_balance()")
    op.execute("DROP TRIGGER IF EXISTS audit_logs_immutable ON audit_logs")
    op.execute("DROP FUNCTION IF EXISTS apex_prevent_audit_mutation()")
    op.execute("DROP INDEX IF EXISTS uq_financial_years_one_current")

    op.drop_constraint("ck_financial_years_date_range", "financial_years", type_="check")
    op.drop_constraint("ck_accounting_periods_date_range", "accounting_periods", type_="check")
    op.drop_constraint("ck_accounts_type", "accounts", type_="check")
    op.drop_constraint("ck_numbering_series_padding", "numbering_series", type_="check")
    op.drop_constraint("ck_numbering_series_next_number", "numbering_series", type_="check")
    op.execute("DROP INDEX IF EXISTS uq_numbering_series_active_document")
    op.drop_constraint(
        "uq_journal_entries_tenant_source", "journal_entries", type_="unique"
    )
    op.drop_constraint(
        "uq_journal_entries_tenant_reference", "journal_entries", type_="unique"
    )
