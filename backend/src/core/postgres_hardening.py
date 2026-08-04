"""PostgreSQL hardening shared by Alembic and fresh-database bootstrap."""

from sqlalchemy import inspect, text


_GLOBAL_TENANT_TABLES = {"audit_logs", "terms_templates"}


def apply_postgres_hardening(connection) -> None:
    """Apply current RLS and accounting hardening idempotently."""
    if connection.dialect.name != "postgresql":
        return

    inspector = inspect(connection)
    for table in inspector.get_table_names():
        columns = {column["name"] for column in inspector.get_columns(table)}
        if "tenant_id" not in columns:
            continue

        quoted = f'"{table}"'
        connection.execute(text(f"ALTER TABLE {quoted} ENABLE ROW LEVEL SECURITY"))
        connection.execute(text(f"ALTER TABLE {quoted} FORCE ROW LEVEL SECURITY"))
        connection.execute(text(f"DROP POLICY IF EXISTS tenant_isolation ON {quoted}"))
        if table in _GLOBAL_TENANT_TABLES:
            condition = (
                "tenant_id IS NULL OR tenant_id::text = "
                "current_setting('app.current_tenant_id', true)"
            )
        else:
            condition = (
                "tenant_id::text = "
                "current_setting('app.current_tenant_id', true)"
            )
        connection.execute(
            text(
                f"CREATE POLICY tenant_isolation ON {quoted} "
                f"USING ({condition}) WITH CHECK ({condition})"
            )
        )

    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS "
            "uq_journal_entries_tenant_reference_fresh "
            "ON journal_entries (tenant_id, reference_number)"
        )
    )
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS "
            "uq_journal_entries_tenant_source_fresh "
            "ON journal_entries (tenant_id, source_type, source_id)"
        )
    )
    connection.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS "
            "uq_financial_years_one_current_fresh "
            "ON financial_years (tenant_id) WHERE is_current"
        )
    )

    connection.execute(
        text(
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
                    RAISE EXCEPTION 'Journal entry % is not balanced', target_entry
                        USING ERRCODE = '23514';
                END IF;
                RETURN NULL;
            END;
            $$ LANGUAGE plpgsql
            """
        )
    )
    connection.execute(text("DROP TRIGGER IF EXISTS ck_journal_entry_balanced ON journal_entries"))
    connection.execute(text("DROP TRIGGER IF EXISTS ck_journal_lines_balanced ON journal_lines"))
    connection.execute(
        text(
            """
            CREATE CONSTRAINT TRIGGER ck_journal_entry_balanced
            AFTER INSERT OR UPDATE ON journal_entries
            DEFERRABLE INITIALLY DEFERRED
            FOR EACH ROW EXECUTE FUNCTION apex_validate_journal_balance()
            """
        )
    )
    connection.execute(
        text(
            """
            CREATE CONSTRAINT TRIGGER ck_journal_lines_balanced
            AFTER INSERT OR UPDATE OR DELETE ON journal_lines
            DEFERRABLE INITIALLY DEFERRED
            FOR EACH ROW EXECUTE FUNCTION apex_validate_journal_balance()
            """
        )
    )

    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_prevent_audit_mutation()
            RETURNS trigger AS $$
            BEGIN
                RAISE EXCEPTION 'Audit log entries are immutable'
                    USING ERRCODE = '55000';
            END;
            $$ LANGUAGE plpgsql
            """
        )
    )
    connection.execute(text("DROP TRIGGER IF EXISTS audit_logs_immutable ON audit_logs"))
    connection.execute(
        text(
            """
            CREATE TRIGGER audit_logs_immutable
            BEFORE UPDATE OR DELETE ON audit_logs
            FOR EACH ROW EXECUTE FUNCTION apex_prevent_audit_mutation()
            """
        )
    )
