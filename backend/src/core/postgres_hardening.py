"""PostgreSQL hardening shared by Alembic and fresh-database bootstrap.

Everything in here is idempotent so it can run from either the guarded
fresh-deploy bootstrap (``alembic upgrade head`` on an empty database) or a
normal revision-by-revision migration.
"""

from sqlalchemy import inspect, text

# Tables whose rows are shared across all tenants (NULL tenant_id is visible to
# every tenant; a tenant's own rows are visible only to that tenant).
_GLOBAL_TENANT_TABLES = {
    "audit_logs",
    "terms_templates",
    "tax_templates",
    "payment_terms",
}

# Tables that intentionally do NOT receive Row-Level Security even though they
# carry a tenant_id column.
#
# tenant_memberships is the cross-tenant access-control registry: login and
# session establishment enumerate a user's memberships across every tenant
# before any tenant context exists.  RLS on this table would hide those rows
# from the restricted application role and break authentication.  It contains
# no tenant accounting data (only user_id / tenant_id / role), and each row is
# itself the grant of access, so column-level visibility is not a concern.
_RLS_EXEMPT_TABLES = {"tenant_memberships"}

# Child / detail tables that get explicit tenant ownership plus a database
# trigger guaranteeing the child's tenant_id matches its parent's tenant_id.
# Format: child_table -> (parent_table, child_fk_column)
_CHILD_TABLES = {
    "invoice_lines": ("invoices", "invoice_id"),
    "bill_lines": ("bills", "bill_id"),
    "journal_lines": ("journal_entries", "entry_id"),
    "purchase_order_lines": ("purchase_orders", "purchase_order_id"),
    "goods_receipt_lines": ("goods_receipts", "goods_receipt_id"),
    "sales_order_lines": ("sales_orders", "sales_order_id"),
    "delivery_challan_lines": ("delivery_challans", "delivery_challan_id"),
    "proforma_invoice_lines": ("proforma_invoices", "proforma_invoice_id"),
    "inventory_adjustment_lines": ("inventory_adjustments", "inventory_adjustment_id"),
    "credit_note_lines": ("credit_notes", "credit_note_id"),
    "debit_note_lines": ("debit_notes", "debit_note_id"),
    "sales_return_lines": ("sales_returns", "sales_return_id"),
    "purchase_return_lines": ("purchase_returns", "purchase_return_id"),
    "recurring_invoice_items": ("recurring_invoices", "recurring_invoice_id"),
}


def _table_has_column(connection, table: str, column: str) -> bool:
    try:
        columns = {
            col["name"] for col in inspect(connection).get_columns(table)
        }
    except Exception:
        return False
    return column in columns


def _apply_rls_policy(connection, table: str) -> None:
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


def _apply_child_table_hardening(connection) -> None:
    """Explicit tenant ownership for child tables: RLS + tenant-match trigger."""
    for child, (parent, fk_column) in _CHILD_TABLES.items():
        if not _table_has_column(connection, child, "tenant_id"):
            continue
        _apply_rls_policy(connection, child)

        trigger_name = f"ck_{child}_tenant_matches_parent"
        function_name = f"apex_{child}_tenant_matches_parent()"
        quoted_child = f'"{child}"'
        quoted_parent = f'"{parent}"'

        connection.execute(
            text(
                f"""
                CREATE OR REPLACE FUNCTION {function_name}
                RETURNS trigger AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM {quoted_parent}
                     WHERE id = NEW.{fk_column};
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.{fk_column}
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql SECURITY DEFINER
                   SET search_path = public, pg_catalog
                """
            )
        )
        connection.execute(
            text(f"DROP TRIGGER IF EXISTS {trigger_name} ON {quoted_child}")
        )
        connection.execute(
            text(
                f"CREATE TRIGGER {trigger_name} "
                f"BEFORE INSERT OR UPDATE OF tenant_id, {fk_column} ON {quoted_child} "
                f"FOR EACH ROW EXECUTE FUNCTION {function_name}"
            )
        )


# Payment allocation join rows: the allocation's tenant must match BOTH the
# payment it belongs to AND the invoice/bill it allocates against.  Format:
# table -> (payment_table, payment_fk, document_table, document_fk).
_PAYMENT_ALLOCATION_TABLES = {
    "payment_allocations": ("payments", "payment_id", "invoices", "invoice_id"),
    "bill_payment_allocations": ("bill_payments", "payment_id", "bills", "bill_id"),
}

# Columns that may be changed in place on an otherwise immutable journal entry.
# Mirrors the ORM guard in models.py: only reversal/correction linkage
# bookkeeping.  Everything else (amounts are on lines; identity, dating,
# source linkage, lock state, attribution) is append-only history.
_JOURNAL_ENTRY_MUTABLE_META = frozenset({
    "reversed_by",
    "reversed_at",
    "reversal_transaction_id",
    "reverses_transaction_id",
    "replacement_transaction_id",
    "updated_at",
})

# Columns that may change in place on a stock movement.  Mirrors the ORM guard.
_STOCK_LEDGER_MUTABLE_META = frozenset({
    "reversal_movement_id",
    "reversed_by",
    "reversed_at",
})


def _apply_payment_allocation_hardening(connection) -> None:
    """RLS + two-parent tenant-consistency enforcement for allocation rows.

    payment_allocations links a payments row to an invoices row;
    bill_payment_allocations links bill_payments to bills.  Both sides must
    belong to the allocation's tenant or the link is a cross-tenant leak.
    PostgreSQL itself rejects any such link via a BEFORE trigger.
    """
    if any(
        not _table_has_column(connection, table, "tenant_id")
        for table in _PAYMENT_ALLOCATION_TABLES
    ):
        return
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_allocation_tenant_matches_parents()
            RETURNS trigger AS $$
            DECLARE
                payment_tenant uuid;
                document_tenant uuid;
            BEGIN
                IF NEW.tenant_id IS NULL THEN
                    RAISE EXCEPTION 'allocation row % has no tenant_id', TG_TABLE_NAME
                        USING ERRCODE = '23514';
                END IF;
                IF TG_TABLE_NAME = 'payment_allocations' THEN
                    SELECT tenant_id INTO payment_tenant FROM payments WHERE id = NEW.payment_id;
                    SELECT tenant_id INTO document_tenant FROM invoices WHERE id = NEW.invoice_id;
                ELSIF TG_TABLE_NAME = 'bill_payment_allocations' THEN
                    SELECT tenant_id INTO payment_tenant FROM bill_payments WHERE id = NEW.payment_id;
                    SELECT tenant_id INTO document_tenant FROM bills WHERE id = NEW.bill_id;
                ELSE
                    RAISE EXCEPTION 'unexpected table %', TG_TABLE_NAME
                        USING ERRCODE = '22000';
                END IF;
                IF payment_tenant IS NULL OR document_tenant IS NULL THEN
                    RAISE EXCEPTION 'allocation row % references a missing parent', TG_TABLE_NAME
                        USING ERRCODE = '23503';
                END IF;
                IF NEW.tenant_id <> payment_tenant OR NEW.tenant_id <> document_tenant THEN
                    RAISE EXCEPTION 'allocation % tenant % must match payment tenant % and document tenant %',
                        TG_TABLE_NAME, NEW.tenant_id, payment_tenant, document_tenant
                        USING ERRCODE = '23514';
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )
    for table, (_, payment_fk, _, document_fk) in _PAYMENT_ALLOCATION_TABLES.items():
        quoted = f'"{table}"'
        _apply_rls_policy(connection, table)
        connection.execute(
            text(f"DROP TRIGGER IF EXISTS ck_{table}_tenant_matches_parents ON {quoted}")
        )
        connection.execute(
            text(
                f"CREATE TRIGGER ck_{table}_tenant_matches_parents "
                f"BEFORE INSERT OR UPDATE OF tenant_id, {payment_fk}, {document_fk} ON {quoted} "
                f"FOR EACH ROW EXECUTE FUNCTION apex_allocation_tenant_matches_parents()"
            )
        )


def _apply_ledger_immutability(connection) -> None:
    """PostgreSQL-level append-only enforcement for the accounting ledger.

    ORM listeners (models.py) are a convenience for the application; raw SQL
    can bypass them.  These triggers make the ledger immutable at the database
    itself for EVERY role (superuser included):

    * journal_entries  — NEVER updated (except reversal/correction linkage
      metadata) and NEVER deleted.  Corrections and year-end reopen are done
      with REVERSAL entries, never by rewriting or deleting history.
    * journal_lines    — NEVER updated, NEVER deleted.
    * stock_ledger     — NEVER updated (except reversal-linkage metadata),
      NEVER deleted.

    There is deliberately NO client-settable bypass for routine writes: a
    transaction-scoped GUC that named eligible source types would let any role
    that holds DELETE on the ledger tables destroy accounting history with raw
    SQL.  Append-only means append-only.

    The one designed exception is the OTP-gated company purge
    (POST /api/v1/purge/verify).  It is a full tenant wipe, so the delete
    guards permit deletion of ledger rows ONLY while the transaction-scoped
    GUC ``app.purge_tenant_id`` names the exact tenant being purged — the
    guard compares the row's own tenant_id against the flag, so a purge can
    never delete another tenant's accounting history, and the flag evaporates
    with the transaction (commit or rollback).  This mirrors the existing RLS
    tenant scoping via ``app.current_tenant_id`` set in src/core/database.py.
    """
    if not (
        _table_has_column(connection, "journal_entries", "id")
        and _table_has_column(connection, "journal_lines", "id")
        and _table_has_column(connection, "stock_ledger", "id")
    ):
        return
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_guard_journal_entries_update()
            RETURNS trigger AS $$
            BEGIN
                IF NEW.is_locked IS DISTINCT FROM OLD.is_locked THEN
                    RAISE EXCEPTION 'journal_entries is append-only: lock state cannot change'
                        USING ERRCODE = '55000';
                END IF;
                IF NOT OLD.is_locked THEN
                    -- Pre-existing unlocked entries remain editable (legacy
                    -- records predate the append-only guarantee).
                    RETURN NEW;
                END IF;
                IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
                   OR NEW.entry_date IS DISTINCT FROM OLD.entry_date
                   OR NEW.reference_number IS DISTINCT FROM OLD.reference_number
                   OR NEW.description IS DISTINCT FROM OLD.description
                   OR NEW.source_type IS DISTINCT FROM OLD.source_type
                   OR NEW.source_id IS DISTINCT FROM OLD.source_id
                   OR NEW.created_by IS DISTINCT FROM OLD.created_by
                   OR NEW.posted_by IS DISTINCT FROM OLD.posted_by
                   OR NEW.posted_at IS DISTINCT FROM OLD.posted_at
                   OR NEW.source_channel IS DISTINCT FROM OLD.source_channel
                   OR NEW.original_transaction_id IS DISTINCT FROM OLD.original_transaction_id
                THEN
                    RAISE EXCEPTION 'journal_entries is append-only; only reversal/correction metadata may change. Create a reversal entry instead.'
                        USING ERRCODE = '55000';
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_guard_journal_entries_delete()
            RETURNS trigger AS $$
            BEGIN
                IF current_setting('app.purge_tenant_id', true) = OLD.tenant_id::text THEN
                    RETURN OLD;
                END IF;
                RAISE EXCEPTION 'journal_entries is append-only accounting history and can never be deleted; create a reversal entry instead'
                    USING ERRCODE = '55000';
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_guard_journal_lines_update()
            RETURNS trigger AS $$
            BEGIN
                RAISE EXCEPTION 'journal_lines is immutable accounting history; create a reversal entry instead'
                    USING ERRCODE = '55000';
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_guard_journal_lines_delete()
            RETURNS trigger AS $$
            BEGIN
                IF current_setting('app.purge_tenant_id', true) = OLD.tenant_id::text THEN
                    RETURN OLD;
                END IF;
                RAISE EXCEPTION 'journal_lines is immutable accounting history and can never be deleted; create a reversal entry instead'
                    USING ERRCODE = '55000';
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_guard_stock_ledger_update()
            RETURNS trigger AS $$
            BEGIN
                IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
                   OR NEW.product_id IS DISTINCT FROM OLD.product_id
                   OR NEW.warehouse_id IS DISTINCT FROM OLD.warehouse_id
                   OR NEW.reference_type IS DISTINCT FROM OLD.reference_type
                   OR NEW.reference_id IS DISTINCT FROM OLD.reference_id
                   OR NEW.quantity IS DISTINCT FROM OLD.quantity
                   OR NEW.balance_quantity IS DISTINCT FROM OLD.balance_quantity
                   OR NEW.rate IS DISTINCT FROM OLD.rate
                   OR NEW.created_at IS DISTINCT FROM OLD.created_at
                   OR NEW.created_by IS DISTINCT FROM OLD.created_by
                   OR NEW.source_channel IS DISTINCT FROM OLD.source_channel
                   OR NEW.reverses_movement_id IS DISTINCT FROM OLD.reverses_movement_id
                THEN
                    RAISE EXCEPTION 'stock_ledger is append-only; only reversal-linkage metadata may change. Create a reversal movement instead.'
                        USING ERRCODE = '55000';
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_guard_stock_ledger_delete()
            RETURNS trigger AS $$
            BEGIN
                IF current_setting('app.purge_tenant_id', true) = OLD.tenant_id::text THEN
                    RETURN OLD;
                END IF;
                RAISE EXCEPTION 'stock_ledger is append-only inventory history; create a reversal movement instead'
                    USING ERRCODE = '55000';
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
            """
        )
    )

    connection.execute(text("DROP TRIGGER IF EXISTS ck_journal_entries_immutable ON journal_entries"))
    connection.execute(text("DROP TRIGGER IF EXISTS ck_journal_entries_no_delete ON journal_entries"))
    connection.execute(text("DROP TRIGGER IF EXISTS ck_journal_lines_immutable ON journal_lines"))
    connection.execute(text("DROP TRIGGER IF EXISTS ck_journal_lines_no_delete ON journal_lines"))
    connection.execute(text("DROP TRIGGER IF EXISTS ck_stock_ledger_immutable ON stock_ledger"))
    connection.execute(text("DROP TRIGGER IF EXISTS ck_stock_ledger_no_delete ON stock_ledger"))

    connection.execute(
        text(
            "CREATE TRIGGER ck_journal_entries_immutable "
            "BEFORE UPDATE ON journal_entries "
            "FOR EACH ROW EXECUTE FUNCTION apex_guard_journal_entries_update()"
        )
    )
    connection.execute(
        text(
            "CREATE TRIGGER ck_journal_entries_no_delete "
            "BEFORE DELETE ON journal_entries "
            "FOR EACH ROW EXECUTE FUNCTION apex_guard_journal_entries_delete()"
        )
    )
    connection.execute(
        text(
            "CREATE TRIGGER ck_journal_lines_immutable "
            "BEFORE UPDATE ON journal_lines "
            "FOR EACH ROW EXECUTE FUNCTION apex_guard_journal_lines_update()"
        )
    )
    connection.execute(
        text(
            "CREATE TRIGGER ck_journal_lines_no_delete "
            "BEFORE DELETE ON journal_lines "
            "FOR EACH ROW EXECUTE FUNCTION apex_guard_journal_lines_delete()"
        )
    )
    connection.execute(
        text(
            "CREATE TRIGGER ck_stock_ledger_immutable "
            "BEFORE UPDATE ON stock_ledger "
            "FOR EACH ROW EXECUTE FUNCTION apex_guard_stock_ledger_update()"
        )
    )
    connection.execute(
        text(
            "CREATE TRIGGER ck_stock_ledger_no_delete "
            "BEFORE DELETE ON stock_ledger "
            "FOR EACH ROW EXECUTE FUNCTION apex_guard_stock_ledger_delete()"
        )
    )


def _ensure_tenant_enumerator(connection) -> None:
    """Controlled cross-tenant enumeration for scheduled maintenance tasks.

    Ordinary application/worker roles never bypass RLS.  Instead they call this
    SECURITY DEFINER function (owned by the migration role, which has
    BYPASSRLS) to obtain only the tenant ids and legal names of active tenants
    — never tenant accounting data.  Per-tenant processing then runs under a
    normal tenant context with RLS enforced.
    """
    connection.execute(
        text(
            """
            CREATE OR REPLACE FUNCTION apex_list_active_tenant_ids()
            RETURNS TABLE (tenant_id uuid, legal_name text)
            LANGUAGE sql
            SECURITY DEFINER
            SET search_path = public, pg_catalog
            AS $$
                SELECT id, legal_name
                  FROM tenants
                 WHERE deleted_at IS NULL
                 ORDER BY legal_name
            $$
            """
        )
    )
    # Grant execute to the restricted roles if they exist (they may not in a
    # plain dev database that never ran the role bootstrap).
    connection.execute(
        text(
            """
            DO $$
            DECLARE
                r text;
            BEGIN
                FOREACH r IN ARRAY ARRAY['apexbooks_api', 'apexbooks_worker']
                LOOP
                    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
                        EXECUTE format(
                            'GRANT EXECUTE ON FUNCTION apex_list_active_tenant_ids() TO %I',
                            r
                        );
                    END IF;
                END LOOP;
            END
            $$;
            """
        )
    )


def apply_postgres_hardening(connection) -> None:
    """Apply current RLS and accounting hardening idempotently."""
    if connection.dialect.name != "postgresql":
        return

    inspector = inspect(connection)
    for table in inspector.get_table_names():
        if table in _RLS_EXEMPT_TABLES:
            # Registry tables must be visible across tenants (e.g. login
            # enumerates a user's memberships before tenant context exists).
            # Explicitly remove any previously-applied RLS.
            quoted = f'"{table}"'
            connection.execute(
                text(f"DROP POLICY IF EXISTS tenant_isolation ON {quoted}")
            )
            connection.execute(
                text(f"ALTER TABLE {quoted} DISABLE ROW LEVEL SECURITY")
            )
            connection.execute(
                text(f"ALTER TABLE {quoted} NO FORCE ROW LEVEL SECURITY")
            )
            continue
        columns = {column["name"] for column in inspector.get_columns(table)}
        if "tenant_id" not in columns:
            continue
        _apply_rls_policy(connection, table)

    _apply_child_table_hardening(connection)
    _apply_payment_allocation_hardening(connection)
    _apply_ledger_immutability(connection)
    _ensure_tenant_enumerator(connection)

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
            $$ LANGUAGE plpgsql SECURITY DEFINER
               SET search_path = public, pg_catalog
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
