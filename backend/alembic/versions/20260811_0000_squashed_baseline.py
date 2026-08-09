"""Squashed baseline: IMMUTABLE schema snapshot for fresh PostgreSQL deployments.

Revision ID: 20260811_0000_squashed_baseline
Revises: 20260810_0001
Create Date: 2026-08-11

This revision is a committed, frozen snapshot of the complete PostgreSQL
schema — tables, sequences, indexes, constraints, RLS policies, FORCE ROW
LEVEL SECURITY, tenant-consistency / ledger-immutability / balance triggers
and the controlled tenant enumerator — captured from a real database built by
the historical migration chain.  It intentionally does NOT import the ORM
models or any runtime hardening module, and it does NOT call
Base.metadata.create_all():

* The SQL below is a literal string.  Changing the ORM models next month (for
  example adding ``Invoice.new_column``) does NOT change what this revision
  creates, so a later migration that adds that column will never collide with
  the baseline.
* ``upgrade()`` creates the schema only when the database is genuinely empty
  (no ``tenants`` table).  Deployments that already ran the legacy chain have
  this exact schema, so the revision is recorded and the next migration
  continues normally.
* Fresh deployments reach this revision via ``alembic/env.py``, which stamps
  the legacy head (20260810_0001) on an empty database — the baseline is the
  squashed embodiment of that whole chain — and then builds everything from
  this snapshot.

The snapshot was produced by:

    pg_dump --schema-only --no-owner --no-privileges --no-comments \
        --exclude-table=alembic_version

against a database migrated to the pre-squash head, after the append-only
ledger triggers were finalized.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "20260811_0000_squashed_baseline"
down_revision: Union[str, Sequence[str], None] = "20260810_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# The immutable snapshot.  Do not edit by hand — regenerate it only by
# rebuilding a database at the pre-squash head and re-embedding a fresh
# pg_dump (and even then only as a deliberate new baseline).
_BASELINE_SQL = r"""--
--

SET search_path TO public, pg_catalog;

--
-- Name: apex_allocation_tenant_matches_parents(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_allocation_tenant_matches_parents() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
            $$;

--
-- Name: apex_bill_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_bill_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "bills"
                     WHERE id = NEW.bill_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.bill_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_credit_note_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_credit_note_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "credit_notes"
                     WHERE id = NEW.credit_note_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.credit_note_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_debit_note_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_debit_note_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "debit_notes"
                     WHERE id = NEW.debit_note_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.debit_note_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_delivery_challan_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_delivery_challan_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "delivery_challans"
                     WHERE id = NEW.delivery_challan_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.delivery_challan_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_goods_receipt_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_goods_receipt_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "goods_receipts"
                     WHERE id = NEW.goods_receipt_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.goods_receipt_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_guard_journal_entries_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_guard_journal_entries_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
            BEGIN
                RAISE EXCEPTION 'journal_entries is append-only accounting history and can never be deleted; create a reversal entry instead'
                    USING ERRCODE = '55000';
            END;
            $$;

--
-- Name: apex_guard_journal_entries_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_guard_journal_entries_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
            $$;

--
-- Name: apex_guard_journal_lines_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_guard_journal_lines_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
            BEGIN
                RAISE EXCEPTION 'journal_lines is immutable accounting history and can never be deleted; create a reversal entry instead'
                    USING ERRCODE = '55000';
            END;
            $$;

--
-- Name: apex_guard_journal_lines_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_guard_journal_lines_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
            BEGIN
                RAISE EXCEPTION 'journal_lines is immutable accounting history; create a reversal entry instead'
                    USING ERRCODE = '55000';
            END;
            $$;

--
-- Name: apex_guard_stock_ledger_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_guard_stock_ledger_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
            BEGIN
                RAISE EXCEPTION 'stock_ledger is append-only inventory history; create a reversal movement instead'
                    USING ERRCODE = '55000';
            END;
            $$;

--
-- Name: apex_guard_stock_ledger_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_guard_stock_ledger_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
            $$;

--
-- Name: apex_inventory_adjustment_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_inventory_adjustment_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "inventory_adjustments"
                     WHERE id = NEW.inventory_adjustment_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.inventory_adjustment_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_invoice_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_invoice_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "invoices"
                     WHERE id = NEW.invoice_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.invoice_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_journal_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_journal_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "journal_entries"
                     WHERE id = NEW.entry_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.entry_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_list_active_tenant_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_list_active_tenant_ids() RETURNS TABLE(tenant_id uuid, legal_name text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
            BEGIN
                RETURN QUERY SELECT id, legal_name
                  FROM tenants
                 WHERE deleted_at IS NULL
                 ORDER BY legal_name;
            END
            $$;

--
-- Name: apex_prevent_audit_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_prevent_audit_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            BEGIN
                RAISE EXCEPTION 'Audit log entries are immutable'
                    USING ERRCODE = '55000';
            END;
            $$;

--
-- Name: apex_proforma_invoice_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_proforma_invoice_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "proforma_invoices"
                     WHERE id = NEW.proforma_invoice_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.proforma_invoice_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_purchase_order_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_purchase_order_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "purchase_orders"
                     WHERE id = NEW.purchase_order_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.purchase_order_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_purchase_return_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_purchase_return_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "purchase_returns"
                     WHERE id = NEW.purchase_return_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.purchase_return_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_recurring_invoice_items_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_recurring_invoice_items_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "recurring_invoices"
                     WHERE id = NEW.recurring_invoice_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.recurring_invoice_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_sales_order_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_sales_order_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "sales_orders"
                     WHERE id = NEW.sales_order_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.sales_order_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_sales_return_lines_tenant_matches_parent(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_sales_return_lines_tenant_matches_parent() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
                DECLARE
                    parent_tenant uuid;
                BEGIN
                    IF NEW.tenant_id IS NULL THEN
                        RAISE EXCEPTION 'child row % has no tenant_id', TG_TABLE_NAME
                            USING ERRCODE = '23514';
                    END IF;
                    SELECT tenant_id INTO parent_tenant
                      FROM "sales_returns"
                     WHERE id = NEW.sales_return_id;
                    IF parent_tenant IS NULL THEN
                        RAISE EXCEPTION 'child row % references missing parent %',
                            TG_TABLE_NAME, NEW.sales_return_id
                            USING ERRCODE = '23503';
                    END IF;
                    IF NEW.tenant_id <> parent_tenant THEN
                        RAISE EXCEPTION 'child row % tenant % does not match parent tenant %',
                            TG_TABLE_NAME, NEW.tenant_id, parent_tenant
                            USING ERRCODE = '23514';
                    END IF;
                    RETURN NEW;
                END;
                $$;

--
-- Name: apex_validate_journal_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apex_validate_journal_balance() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
            $$;

--
-- Name: accounting_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounting_periods (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    period_name character varying(50) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    is_closed boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_accounting_periods_date_range CHECK ((start_date <= end_date)),
    CONSTRAINT ck_accounting_periods_is_closed CHECK ((is_closed = ANY (ARRAY[true, false])))
);

ALTER TABLE ONLY public.accounting_periods FORCE ROW LEVEL SECURITY;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    code character varying(50) NOT NULL,
    account_type character varying(50) NOT NULL,
    account_group character varying(100),
    parent_id uuid,
    opening_balance numeric(15,4) NOT NULL,
    current_balance numeric(15,4) NOT NULL,
    is_active boolean NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_accounts_type CHECK (((account_type)::text = ANY ((ARRAY['ASSET'::character varying, 'LIABILITY'::character varying, 'EQUITY'::character varying, 'REVENUE'::character varying, 'EXPENSE'::character varying])::text[])))
);

ALTER TABLE ONLY public.accounts FORCE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid NOT NULL,
    tenant_id uuid,
    actor_id uuid,
    actor_email character varying(255),
    action character varying(100) NOT NULL,
    entity_type character varying(50) NOT NULL,
    entity_id uuid,
    before_state json,
    after_state json,
    ip_address character varying(45),
    user_agent character varying(512),
    "timestamp" timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.audit_logs FORCE ROW LEVEL SECURITY;

--
-- Name: bank_reconciliations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bank_reconciliations (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    bank_transaction_id uuid NOT NULL,
    payment_id uuid,
    bill_payment_id uuid,
    amount numeric(15,4) NOT NULL,
    notes text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_bank_reconciliations_single_payment CHECK ((((payment_id IS NOT NULL) AND (bill_payment_id IS NULL)) OR ((payment_id IS NULL) AND (bill_payment_id IS NOT NULL))))
);

ALTER TABLE ONLY public.bank_reconciliations FORCE ROW LEVEL SECURITY;

--
-- Name: bank_statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bank_statements (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    banking_profile_id uuid NOT NULL,
    statement_date date NOT NULL,
    starting_balance numeric(15,4) NOT NULL,
    ending_balance numeric(15,4) NOT NULL,
    currency character varying(10) NOT NULL,
    status character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.bank_statements FORCE ROW LEVEL SECURITY;

--
-- Name: bank_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bank_transactions (
    id uuid NOT NULL,
    bank_statement_id uuid NOT NULL,
    transaction_date date NOT NULL,
    amount numeric(15,4) NOT NULL,
    description text,
    reference_number character varying(50),
    status character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

--
-- Name: banking_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banking_profiles (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    bank_name character varying(150) NOT NULL,
    account_number character varying(50) NOT NULL,
    ifsc_code character varying(20) NOT NULL,
    branch_name character varying(150),
    account_holder_name character varying(150) NOT NULL,
    upi_id character varying(100),
    is_primary boolean NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.banking_profiles FORCE ROW LEVEL SECURITY;

--
-- Name: bill_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bill_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    bill_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.bill_lines FORCE ROW LEVEL SECURITY;

--
-- Name: bill_payment_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bill_payment_allocations (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    payment_id uuid NOT NULL,
    bill_id uuid NOT NULL,
    amount numeric(15,4) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_bill_payment_allocations_amount CHECK ((amount > (0)::numeric))
);

ALTER TABLE ONLY public.bill_payment_allocations FORCE ROW LEVEL SECURITY;

--
-- Name: bill_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bill_payments (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    payment_number character varying(50) NOT NULL,
    payment_date date NOT NULL,
    payment_mode character varying(20) NOT NULL,
    amount numeric(15,4) NOT NULL,
    reference_number character varying(50),
    description text,
    status character varying(20) NOT NULL,
    cancelled_at timestamp with time zone,
    cancellation_reason text,
    created_by uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_bill_payments_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT ck_bill_payments_payment_mode CHECK (((payment_mode)::text = ANY ((ARRAY['CASH'::character varying, 'BANK'::character varying, 'UPI'::character varying, 'POS'::character varying, 'CHEQUE'::character varying, 'NEFT_RTGS'::character varying, 'OTHER'::character varying])::text[]))),
    CONSTRAINT ck_bill_payments_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.bill_payments FORCE ROW LEVEL SECURITY;

--
-- Name: bills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bills (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    bill_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    discount_total numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    shipping_charges numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    amount_paid numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    notes text,
    terms_and_conditions text,
    reference_number character varying(50),
    vyapar_custom_fields json NOT NULL,
    tds_rate numeric(5,2) NOT NULL,
    tds_amount numeric(15,4) NOT NULL,
    itc_eligible boolean NOT NULL,
    is_gst_inclusive boolean NOT NULL,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_bills_amount_paid CHECK ((amount_paid <= total)),
    CONSTRAINT ck_bills_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'UNPAID'::character varying, 'PARTIALLY_PAID'::character varying, 'PAID'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT ck_bills_total_balance CHECK ((round(total, 2) = round(((((((((subtotal + cgst_amount) + sgst_amount) + igst_amount) + utgst_amount) + cess_amount) + round_off) - discount_total) + shipping_charges), 2)))
);

ALTER TABLE ONLY public.bills FORCE ROW LEVEL SECURITY;

--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    gstin character varying(15),
    address json NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.branches FORCE ROW LEVEL SECURITY;

--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    email character varying(255),
    phone character varying(20),
    contact_type character varying(10) NOT NULL,
    gstin character varying(15),
    pan character varying(10),
    registration_type character varying(20) NOT NULL,
    billing_address json,
    shipping_address json,
    state_code character varying(2),
    is_active boolean NOT NULL,
    opening_balance numeric(15,4) NOT NULL,
    credit_balance numeric(15,4) NOT NULL,
    custom_fields json NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone
);

ALTER TABLE ONLY public.contacts FORCE ROW LEVEL SECURITY;

--
-- Name: credit_note_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_note_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    credit_note_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity numeric(15,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8),
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.credit_note_lines FORCE ROW LEVEL SECURITY;

--
-- Name: credit_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_notes (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid,
    credit_note_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    reason character varying(255) NOT NULL,
    restock_items boolean NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    total numeric(15,4) NOT NULL,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_credit_notes_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'ISSUED'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT ck_credit_notes_total_balance CHECK ((round(total, 2) = round(((((((subtotal + cgst_amount) + sgst_amount) + igst_amount) + utgst_amount) + cess_amount) + round_off), 2)))
);

ALTER TABLE ONLY public.credit_notes FORCE ROW LEVEL SECURITY;

--
-- Name: debit_note_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.debit_note_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    debit_note_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity numeric(15,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8),
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.debit_note_lines FORCE ROW LEVEL SECURITY;

--
-- Name: debit_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.debit_notes (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid,
    debit_note_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    reason character varying(255) NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    total numeric(15,4) NOT NULL,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_debit_notes_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'ISSUED'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT ck_debit_notes_total_balance CHECK ((round(total, 2) = round(((((((subtotal + cgst_amount) + sgst_amount) + igst_amount) + utgst_amount) + cess_amount) + round_off), 2)))
);

ALTER TABLE ONLY public.debit_notes FORCE ROW LEVEL SECURITY;

--
-- Name: delivery_challan_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_challan_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    delivery_challan_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.delivery_challan_lines FORCE ROW LEVEL SECURITY;

--
-- Name: delivery_challans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_challans (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    source_sales_order_id uuid,
    converted_to_invoice_id uuid,
    challan_number character varying(50) NOT NULL,
    challan_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    discount_total numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_delivery_challans_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'ISSUED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.delivery_challans FORCE ROW LEVEL SECURITY;

--
-- Name: eway_bills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eway_bills (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid,
    bill_id uuid,
    eway_bill_number character varying(12),
    status character varying(20) NOT NULL,
    supply_type character varying(10) NOT NULL,
    sub_supply_type character varying(20) NOT NULL,
    transporter_id character varying(15),
    transporter_name character varying(150),
    trans_doc_number character varying(50),
    trans_doc_date date,
    trans_distance integer NOT NULL,
    trans_mode character varying(10) NOT NULL,
    vehicle_number character varying(20) NOT NULL,
    vehicle_type character varying(20) NOT NULL,
    valid_until timestamp with time zone,
    vehicle_history json,
    cancel_reason character varying(20),
    cancel_remarks character varying(100),
    cancel_date timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_eway_bills_single_parent CHECK ((((invoice_id IS NOT NULL) AND (bill_id IS NULL)) OR ((invoice_id IS NULL) AND (bill_id IS NOT NULL)))),
    CONSTRAINT ck_eway_bills_status CHECK (((status)::text = ANY ((ARRAY['GENERATED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.eway_bills FORCE ROW LEVEL SECURITY;

--
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_categories (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    description text,
    linked_account_id uuid,
    is_active boolean NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.expense_categories FORCE ROW LEVEL SECURITY;

--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    expense_number character varying(50) NOT NULL,
    expense_category_id uuid NOT NULL,
    bank_account_id uuid,
    expense_date date NOT NULL,
    vendor_name character varying(150),
    description text,
    amount numeric(15,4) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    place_of_supply_state_code character varying(2),
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    status character varying(20) NOT NULL,
    notes text,
    reference_number character varying(50),
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_expenses_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.expenses FORCE ROW LEVEL SECURITY;

--
-- Name: financial_year_audits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_year_audits (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    financial_year_id uuid NOT NULL,
    action character varying(50) NOT NULL,
    detail text,
    performed_by uuid,
    created_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.financial_year_audits FORCE ROW LEVEL SECURITY;

--
-- Name: financial_years; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_years (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(50) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status character varying(20) NOT NULL,
    is_current boolean NOT NULL,
    closed_at timestamp with time zone,
    closed_by uuid,
    reopened_at timestamp with time zone,
    reopened_by uuid,
    reopen_reason text,
    journal_entry_id uuid,
    transaction_count integer NOT NULL,
    created_by uuid,
    switched_by uuid,
    last_accessed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_financial_years_date_range CHECK ((start_date <= end_date)),
    CONSTRAINT ck_financial_years_status CHECK (((status)::text = ANY ((ARRAY['CURRENT'::character varying, 'READY_TO_CLOSE'::character varying, 'LOCKED'::character varying, 'ARCHIVED'::character varying])::text[])))
);

ALTER TABLE ONLY public.financial_years FORCE ROW LEVEL SECURITY;

--
-- Name: goods_receipt_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goods_receipt_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    goods_receipt_id uuid NOT NULL,
    purchase_order_line_id uuid,
    product_id uuid NOT NULL,
    quantity_ordered numeric(12,4) NOT NULL,
    quantity_received numeric(12,4) NOT NULL,
    warehouse_id uuid,
    lot_number character varying(100),
    batch_number character varying(100)
);

ALTER TABLE ONLY public.goods_receipt_lines FORCE ROW LEVEL SECURITY;

--
-- Name: goods_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goods_receipts (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    purchase_order_id uuid,
    contact_id uuid,
    receipt_number character varying(50) NOT NULL,
    receipt_date date NOT NULL,
    status character varying(20) NOT NULL,
    notes text,
    confirmed_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_goods_receipts_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'CONFIRMED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.goods_receipts FORCE ROW LEVEL SECURITY;

--
-- Name: gst_returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gst_returns (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    return_type character varying(20) NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    status character varying(20) NOT NULL,
    json_payload json,
    filed_by uuid,
    filed_at timestamp with time zone,
    arn character varying(50),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_gst_returns_status CHECK (((status)::text = ANY ((ARRAY['COMPUTED'::character varying, 'READY_TO_FILE'::character varying, 'FILED'::character varying, 'ACKNOWLEDGED'::character varying])::text[])))
);

ALTER TABLE ONLY public.gst_returns FORCE ROW LEVEL SECURITY;

--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    id uuid NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    tenant_id uuid NOT NULL,
    method character varying(10) NOT NULL,
    path character varying(500) NOT NULL,
    is_processed boolean,
    request_hash character varying(64),
    status character varying(20) NOT NULL,
    response_status integer,
    response_body text,
    response_content_type character varying(100),
    resource_type character varying(100),
    resource_id uuid,
    created_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.idempotency_keys FORCE ROW LEVEL SECURITY;

--
-- Name: integration_connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_connections (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    integration_name character varying(50) NOT NULL,
    external_tenant_id character varying(100) NOT NULL,
    api_key_prefix character varying(20) NOT NULL,
    api_key_hash character varying(64) NOT NULL,
    hmac_secret_encrypted text NOT NULL,
    status character varying(20) NOT NULL,
    clock_skew_seconds integer NOT NULL,
    replay_retention_days integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    disabled_at timestamp with time zone,
    CONSTRAINT ck_integration_connections_status CHECK (((status)::text = ANY ((ARRAY['ENABLED'::character varying, 'DISABLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_connections FORCE ROW LEVEL SECURITY;

--
-- Name: integration_dead_letter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_dead_letter (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    connection_id uuid NOT NULL,
    integration_name character varying(50) NOT NULL,
    direction character varying(10) NOT NULL,
    event_id character varying(100),
    event_name character varying(100) NOT NULL,
    payload_encrypted text NOT NULL,
    payload_hash character varying(64) NOT NULL,
    failure_code character varying(50) NOT NULL,
    failure_message text NOT NULL,
    retry_count integer NOT NULL,
    next_retry_at timestamp with time zone,
    status character varying(20) NOT NULL,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_dead_letter_direction CHECK (((direction)::text = ANY ((ARRAY['INBOUND'::character varying, 'OUTBOUND'::character varying])::text[]))),
    CONSTRAINT ck_integration_dead_letter_status CHECK (((status)::text = ANY ((ARRAY['OPEN'::character varying, 'RETRYING'::character varying, 'RESOLVED'::character varying, 'DISCARDED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_dead_letter FORCE ROW LEVEL SECURITY;

--
-- Name: integration_entity_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_entity_map (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    integration_name character varying(50) NOT NULL,
    entity_type character varying(50) NOT NULL,
    external_id character varying(150) NOT NULL,
    internal_id uuid NOT NULL,
    external_version character varying(100),
    sync_status character varying(20) NOT NULL,
    last_synced_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_entity_map_sync_status CHECK (((sync_status)::text = ANY ((ARRAY['PENDING'::character varying, 'SYNCED'::character varying, 'FAILED'::character varying, 'DISABLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_entity_map FORCE ROW LEVEL SECURITY;

--
-- Name: integration_event_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_event_log (
    id uuid NOT NULL,
    request_id character varying(30) NOT NULL,
    tenant_id uuid,
    connection_id uuid,
    integration_name character varying(50) NOT NULL,
    external_tenant_id character varying(100),
    direction character varying(10) NOT NULL,
    method character varying(10) NOT NULL,
    path character varying(500) NOT NULL,
    event_id character varying(100),
    idempotency_key character varying(255),
    event_name character varying(100),
    source_id character varying(150),
    signature_hash character varying(64),
    payload_hash character varying(64) NOT NULL,
    response_hash character varying(64),
    response_status integer,
    status character varying(20) NOT NULL,
    processing_time_ms integer,
    error_code character varying(50),
    started_at timestamp with time zone NOT NULL,
    processed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_event_log_direction CHECK (((direction)::text = ANY ((ARRAY['INBOUND'::character varying, 'OUTBOUND'::character varying])::text[]))),
    CONSTRAINT ck_integration_event_log_status CHECK (((status)::text = ANY ((ARRAY['PROCESSING'::character varying, 'COMPLETED'::character varying, 'REPLAYED'::character varying, 'REJECTED'::character varying, 'FAILED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_event_log FORCE ROW LEVEL SECURITY;

--
-- Name: integration_inventory_movement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_inventory_movement (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    order_state_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    warehouse_id character varying(150) NOT NULL,
    movement_type character varying(30) NOT NULL,
    quantity_delta integer NOT NULL,
    event_id character varying(100) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_inventory_movement_quantity CHECK ((quantity_delta <> 0)),
    CONSTRAINT ck_integration_inventory_movement_type CHECK (((movement_type)::text = ANY ((ARRAY['RESERVATION'::character varying, 'RESERVATION_RELEASE'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_inventory_movement FORCE ROW LEVEL SECURITY;

--
-- Name: integration_invoice_line_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_invoice_line_map (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    invoice_line_id uuid NOT NULL,
    medusa_line_id character varying(40) NOT NULL,
    apexbooks_invoice_line_id character varying(150) NOT NULL,
    created_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.integration_invoice_line_map FORCE ROW LEVEL SECURITY;

--
-- Name: integration_master_sync_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_master_sync_audit (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    integration_name character varying(50) NOT NULL,
    event_name character varying(100) NOT NULL,
    event_id character varying(100) NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    entity_type character varying(50) NOT NULL,
    external_id character varying(150) NOT NULL,
    old_values json,
    new_values json NOT NULL,
    processing_time_ms integer NOT NULL,
    result character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_master_sync_audit_result CHECK (((result)::text = ANY ((ARRAY['CREATED'::character varying, 'UPDATED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_master_sync_audit FORCE ROW LEVEL SECURITY;

--
-- Name: integration_order_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_order_audit (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    event_name character varying(100) NOT NULL,
    event_id character varying(100) NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    medusa_order_id character varying(40) NOT NULL,
    apexbooks_order_id character varying(150) NOT NULL,
    medusa_customer_id character varying(40) NOT NULL,
    apexbooks_customer_id character varying(150) NOT NULL,
    product_ids json NOT NULL,
    old_values json,
    new_values json NOT NULL,
    execution_time_ms integer NOT NULL,
    result character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_order_audit_result CHECK (((result)::text = ANY ((ARRAY['CREATED'::character varying, 'UPDATED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_order_audit FORCE ROW LEVEL SECURITY;

--
-- Name: integration_order_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_order_state (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    medusa_order_id character varying(40) NOT NULL,
    apexbooks_order_id character varying(150) NOT NULL,
    medusa_customer_id character varying(40) NOT NULL,
    apexbooks_customer_id character varying(150) NOT NULL,
    accounting_reference character varying(50) NOT NULL,
    revision integer NOT NULL,
    status character varying(20) NOT NULL,
    invoice_id uuid,
    apexbooks_invoice_id character varying(150),
    captured_amount_minor integer NOT NULL,
    refunded_amount_minor integer NOT NULL,
    commercial_snapshot json NOT NULL,
    cancellation_reason_code character varying(30),
    cancellation_reason text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_order_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'PARTIALLY_PAID'::character varying, 'PAID'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_order_state FORCE ROW LEVEL SECURITY;

--
-- Name: integration_payment_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_payment_audit (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    event_id character varying(100) NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    medusa_payment_id character varying(40) NOT NULL,
    medusa_order_id character varying(40) NOT NULL,
    apexbooks_payment_id character varying(150) NOT NULL,
    apexbooks_invoice_id character varying(150) NOT NULL,
    capture_sequence integer NOT NULL,
    amount_minor integer NOT NULL,
    old_values json NOT NULL,
    new_values json NOT NULL,
    execution_time_ms integer NOT NULL,
    result character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.integration_payment_audit FORCE ROW LEVEL SECURITY;

--
-- Name: integration_payment_inventory_movement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_payment_inventory_movement (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    order_state_id uuid NOT NULL,
    payment_state_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    warehouse_id character varying(150) NOT NULL,
    movement_type character varying(20) NOT NULL,
    quantity integer NOT NULL,
    available_before integer NOT NULL,
    available_after integer NOT NULL,
    reserved_before integer NOT NULL,
    reserved_after integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_payment_inventory_quantity CHECK ((quantity > 0)),
    CONSTRAINT ck_payment_inventory_type CHECK (((movement_type)::text = 'SALE_OUT'::text))
);

ALTER TABLE ONLY public.integration_payment_inventory_movement FORCE ROW LEVEL SECURITY;

--
-- Name: integration_payment_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_payment_state (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    order_state_id uuid NOT NULL,
    payment_id uuid NOT NULL,
    medusa_payment_id character varying(40) NOT NULL,
    apexbooks_payment_id character varying(150) NOT NULL,
    receipt_id character varying(150) NOT NULL,
    capture_sequence integer NOT NULL,
    currency_code character varying(3) NOT NULL,
    amount_minor integer NOT NULL,
    provider_id character varying(100) NOT NULL,
    transaction_id character varying(150) NOT NULL,
    status character varying(20) NOT NULL,
    captured_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_payment_amount CHECK ((amount_minor > 0)),
    CONSTRAINT ck_integration_payment_status CHECK (((status)::text = 'CAPTURED'::text))
);

ALTER TABLE ONLY public.integration_payment_state FORCE ROW LEVEL SECURITY;

--
-- Name: integration_replay_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_replay_cache (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    connection_id uuid NOT NULL,
    integration_name character varying(50) NOT NULL,
    event_id character varying(100) NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    event_name character varying(100) NOT NULL,
    source_id character varying(150) NOT NULL,
    method character varying(10) NOT NULL,
    path character varying(500) NOT NULL,
    signature_hash character varying(64) NOT NULL,
    request_hash character varying(64) NOT NULL,
    response_hash character varying(64),
    response_status integer,
    response_body_encrypted text,
    status character varying(20) NOT NULL,
    processed_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_integration_replay_status CHECK (((status)::text = ANY ((ARRAY['PROCESSING'::character varying, 'COMPLETED'::character varying])::text[])))
);

ALTER TABLE ONLY public.integration_replay_cache FORCE ROW LEVEL SECURITY;

--
-- Name: integration_synced_customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_synced_customers (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    apexbooks_customer_id character varying(150) NOT NULL,
    medusa_customer_id character varying(40) NOT NULL,
    first_name character varying(75) NOT NULL,
    last_name character varying(75) NOT NULL,
    phone character varying(16) NOT NULL,
    accounting_email character varying(255) NOT NULL,
    gstin character varying(15),
    gst_type character varying(20) NOT NULL,
    billing_address json NOT NULL,
    shipping_address json NOT NULL,
    state_code character varying(2) NOT NULL,
    credit_terms_days integer NOT NULL,
    active boolean NOT NULL,
    source_updated_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.integration_synced_customers FORCE ROW LEVEL SECURITY;

--
-- Name: integration_synced_inventory_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_synced_inventory_levels (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    warehouse_id character varying(150) NOT NULL,
    available_quantity integer NOT NULL,
    reserved_quantity integer NOT NULL,
    source_updated_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_synced_inventory_available CHECK ((available_quantity >= 0)),
    CONSTRAINT ck_synced_inventory_reserved CHECK ((reserved_quantity >= 0))
);

ALTER TABLE ONLY public.integration_synced_inventory_levels FORCE ROW LEVEL SECURITY;

--
-- Name: integration_synced_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_synced_prices (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    amount_minor integer NOT NULL,
    currency_code character varying(3) NOT NULL,
    tax_inclusive boolean NOT NULL,
    price_list_id character varying(100),
    valid_from timestamp with time zone,
    valid_to timestamp with time zone,
    source_updated_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_synced_price_amount CHECK ((amount_minor >= 0))
);

ALTER TABLE ONLY public.integration_synced_prices FORCE ROW LEVEL SECURITY;

--
-- Name: integration_synced_product_variants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_synced_product_variants (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    apexbooks_variant_id character varying(150) NOT NULL,
    medusa_variant_id character varying(40) NOT NULL,
    sku character varying(64) NOT NULL,
    title character varying(150) NOT NULL,
    product_type character varying(10) NOT NULL,
    active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.integration_synced_product_variants FORCE ROW LEVEL SECURITY;

--
-- Name: integration_synced_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_synced_products (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    apexbooks_product_id character varying(150) NOT NULL,
    medusa_product_id character varying(40) NOT NULL,
    title character varying(200) NOT NULL,
    description text NOT NULL,
    categories json NOT NULL,
    images json NOT NULL,
    active boolean NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate_bps integer NOT NULL,
    source_updated_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.integration_synced_products FORCE ROW LEVEL SECURITY;

--
-- Name: inventory_adjustment_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_adjustment_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    inventory_adjustment_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity_change numeric(15,4) NOT NULL,
    unit_cost numeric(15,4) NOT NULL,
    total_change numeric(15,4) NOT NULL,
    reason character varying(255)
);

ALTER TABLE ONLY public.inventory_adjustment_lines FORCE ROW LEVEL SECURITY;

--
-- Name: inventory_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_adjustments (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    adjustment_number character varying(50) NOT NULL,
    adjustment_date date NOT NULL,
    status character varying(20) NOT NULL,
    reason text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_inventory_adjustments_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'CONFIRMED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.inventory_adjustments FORCE ROW LEVEL SECURITY;

--
-- Name: inventory_carry_forwards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_carry_forwards (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    financial_year_id uuid NOT NULL,
    product_id uuid NOT NULL,
    product_name character varying(150) NOT NULL,
    product_sku character varying(50),
    closing_quantity numeric(12,2) NOT NULL,
    closing_value numeric(15,4) NOT NULL,
    unit_rate numeric(15,4) NOT NULL,
    created_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.inventory_carry_forwards FORCE ROW LEVEL SECURITY;

--
-- Name: invoice_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.invoice_lines FORCE ROW LEVEL SECURITY;

--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    source_document_type character varying(30),
    source_document_id uuid,
    invoice_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    discount_total numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    shipping_charges numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    amount_paid numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    irn character varying(64),
    qr_code text,
    e_invoice_status character varying(20) NOT NULL,
    e_invoice_error text,
    notes text,
    terms_and_conditions text,
    reference_number character varying(50),
    vyapar_custom_fields json NOT NULL,
    sales_person_id uuid,
    is_rcm boolean NOT NULL,
    is_gst_inclusive boolean NOT NULL,
    supply_type character varying(20) NOT NULL,
    currency character varying(10) NOT NULL,
    exchange_rate numeric(15,6) NOT NULL,
    tds_rate numeric(5,2) NOT NULL,
    tds_amount numeric(15,4) NOT NULL,
    tcs_rate numeric(5,2) NOT NULL,
    tcs_amount numeric(15,4) NOT NULL,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_invoices_amount_paid CHECK ((amount_paid <= total)),
    CONSTRAINT ck_invoices_amount_paid_nonnegative CHECK ((amount_paid >= (0)::numeric)),
    CONSTRAINT ck_invoices_due_date CHECK ((due_date >= issue_date)),
    CONSTRAINT ck_invoices_e_invoice_status CHECK (((e_invoice_status)::text = ANY ((ARRAY['PENDING'::character varying, 'GENERATED'::character varying, 'CANCELLED'::character varying, 'FAILED'::character varying])::text[]))),
    CONSTRAINT ck_invoices_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'SENT'::character varying, 'PARTIALLY_PAID'::character varying, 'PAID'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT ck_invoices_total_balance CHECK ((round(total, 2) = round(((((((((subtotal + cgst_amount) + sgst_amount) + igst_amount) + utgst_amount) + cess_amount) + round_off) - discount_total) + shipping_charges), 2)))
);

ALTER TABLE ONLY public.invoices FORCE ROW LEVEL SECURITY;

--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    entry_date date NOT NULL,
    reference_number character varying(50),
    description text,
    source_type character varying(20) NOT NULL,
    source_id uuid,
    is_locked boolean NOT NULL,
    created_by uuid,
    posted_by uuid,
    posted_at timestamp with time zone,
    source_channel character varying(20),
    reversed_by uuid,
    reversed_at timestamp with time zone,
    reversal_transaction_id uuid,
    reverses_transaction_id uuid,
    replacement_transaction_id uuid,
    original_transaction_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.journal_entries FORCE ROW LEVEL SECURITY;

--
-- Name: journal_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    entry_id uuid NOT NULL,
    account_id uuid NOT NULL,
    amount numeric(15,4) NOT NULL,
    direction character varying(6) NOT NULL,
    narration text,
    CONSTRAINT ck_journal_lines_amount CHECK ((amount > (0)::numeric)),
    CONSTRAINT ck_journal_lines_direction CHECK (((direction)::text = ANY ((ARRAY['DEBIT'::character varying, 'CREDIT'::character varying])::text[])))
);

ALTER TABLE ONLY public.journal_lines FORCE ROW LEVEL SECURITY;

--
-- Name: numbering_series; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.numbering_series (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    document_type character varying(50) NOT NULL,
    prefix character varying(50) NOT NULL,
    next_number integer NOT NULL,
    suffix character varying(50),
    padding_digits integer NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_numbering_series_next_number CHECK ((next_number > 0)),
    CONSTRAINT ck_numbering_series_padding CHECK (((padding_digits >= 1) AND (padding_digits <= 12)))
);

ALTER TABLE ONLY public.numbering_series FORCE ROW LEVEL SECURITY;

--
-- Name: offline_number_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offline_number_allocations (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    device_id uuid NOT NULL,
    financial_year_id uuid NOT NULL,
    numbering_series_id uuid NOT NULL,
    document_type character varying(50) NOT NULL,
    series character varying(50) NOT NULL,
    prefix character varying(50) NOT NULL,
    suffix character varying(50),
    padding_digits integer NOT NULL,
    range_start integer NOT NULL,
    range_end integer NOT NULL,
    allocated_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone,
    is_active boolean NOT NULL,
    CONSTRAINT ck_offline_number_allocation_range CHECK (((range_start > 0) AND (range_end >= range_start)))
);

ALTER TABLE ONLY public.offline_number_allocations FORCE ROW LEVEL SECURITY;

--
-- Name: opening_balance_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opening_balance_snapshots (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    financial_year_id uuid NOT NULL,
    account_id uuid NOT NULL,
    account_type character varying(50) NOT NULL,
    account_name character varying(150) NOT NULL,
    account_code character varying(50) NOT NULL,
    closing_balance numeric(15,4) NOT NULL,
    direction character varying(6) NOT NULL,
    created_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.opening_balance_snapshots FORCE ROW LEVEL SECURITY;

--
-- Name: password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token character varying(255) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL
);

--
-- Name: payment_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_allocations (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    payment_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    amount numeric(15,4) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_payment_allocations_amount CHECK ((amount > (0)::numeric))
);

ALTER TABLE ONLY public.payment_allocations FORCE ROW LEVEL SECURITY;

--
-- Name: payment_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_terms (
    id uuid NOT NULL,
    tenant_id uuid,
    name character varying(100) NOT NULL,
    due_days integer NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.payment_terms FORCE ROW LEVEL SECURITY;

--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    payment_number character varying(50) NOT NULL,
    payment_date date NOT NULL,
    payment_mode character varying(20) NOT NULL,
    amount numeric(15,4) NOT NULL,
    reference_number character varying(50),
    description text,
    advance_supply_type character varying(10),
    status character varying(20) NOT NULL,
    cancelled_at timestamp with time zone,
    cancellation_reason text,
    created_by uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_payments_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT ck_payments_payment_mode CHECK (((payment_mode)::text = ANY ((ARRAY['CASH'::character varying, 'BANK'::character varying, 'UPI'::character varying, 'POS'::character varying, 'CHEQUE'::character varying, 'NEFT_RTGS'::character varying, 'OTHER'::character varying])::text[]))),
    CONSTRAINT ck_payments_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.payments FORCE ROW LEVEL SECURITY;

--
-- Name: period_lock_audits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.period_lock_audits (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    period_date date NOT NULL,
    action character varying(10) NOT NULL,
    locked_by uuid NOT NULL,
    locked_at timestamp with time zone NOT NULL,
    note text
);

ALTER TABLE ONLY public.period_lock_audits FORCE ROW LEVEL SECURITY;

--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    sku character varying(50),
    barcode character varying(64),
    hsn_sac character varying(8) NOT NULL,
    product_type character varying(10) NOT NULL,
    uom character varying(10) NOT NULL,
    sales_price numeric(15,4) NOT NULL,
    purchase_price numeric(15,4) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    opening_stock numeric(12,2) NOT NULL,
    current_stock numeric(12,2) NOT NULL,
    reorder_level numeric(12,2) NOT NULL,
    party_item_rates json NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_products_purchase_price CHECK ((purchase_price >= (0)::numeric)),
    CONSTRAINT ck_products_sales_price CHECK ((sales_price >= (0)::numeric))
);

ALTER TABLE ONLY public.products FORCE ROW LEVEL SECURITY;

--
-- Name: proforma_invoice_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proforma_invoice_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    proforma_invoice_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.proforma_invoice_lines FORCE ROW LEVEL SECURITY;

--
-- Name: proforma_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proforma_invoices (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    proforma_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    discount_total numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    converted_to_invoice_id uuid,
    converted_to_sales_order_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_proforma_invoices_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'ISSUED'::character varying, 'CONVERTED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.proforma_invoices FORCE ROW LEVEL SECURITY;

--
-- Name: purchase_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_order_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    purchase_order_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.purchase_order_lines FORCE ROW LEVEL SECURITY;

--
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_orders (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    po_number character varying(50) NOT NULL,
    order_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    discount_total numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    amount_received numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_purchase_orders_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'CONFIRMED'::character varying, 'RECEIVED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.purchase_orders FORCE ROW LEVEL SECURITY;

--
-- Name: purchase_return_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_return_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    purchase_return_id uuid NOT NULL,
    bill_line_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8),
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.purchase_return_lines FORCE ROW LEVEL SECURITY;

--
-- Name: purchase_returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_returns (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    bill_id uuid NOT NULL,
    return_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    notes text,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_purchase_returns_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT ck_purchase_returns_total_balance CHECK ((round(total, 2) = round(((((((subtotal + cgst_amount) + sgst_amount) + igst_amount) + utgst_amount) + cess_amount) + round_off), 2)))
);

ALTER TABLE ONLY public.purchase_returns FORCE ROW LEVEL SECURITY;

--
-- Name: recurring_invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurring_invoice_items (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    recurring_invoice_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL
);

ALTER TABLE ONLY public.recurring_invoice_items FORCE ROW LEVEL SECURITY;

--
-- Name: recurring_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurring_invoices (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    source_invoice_id uuid,
    template_name character varying(150) NOT NULL,
    is_active boolean NOT NULL,
    frequency character varying(20) NOT NULL,
    interval_count integer NOT NULL,
    next_date date NOT NULL,
    end_mode character varying(20) NOT NULL,
    end_date date,
    max_occurrences integer,
    occurrences_created integer NOT NULL,
    last_generated date,
    currency character varying(10) NOT NULL,
    exchange_rate numeric(15,6) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    notes text,
    terms_and_conditions text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_recurring_invoices_end_mode CHECK (((end_mode)::text = ANY ((ARRAY['NEVER'::character varying, 'ON_DATE'::character varying, 'AFTER_N'::character varying])::text[]))),
    CONSTRAINT ck_recurring_invoices_frequency CHECK (((frequency)::text = ANY ((ARRAY['WEEKLY'::character varying, 'MONTHLY'::character varying, 'QUARTERLY'::character varying, 'YEARLY'::character varying])::text[])))
);

ALTER TABLE ONLY public.recurring_invoices FORCE ROW LEVEL SECURITY;

--
-- Name: sales_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_order_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    discount numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8) NOT NULL,
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.sales_order_lines FORCE ROW LEVEL SECURITY;

--
-- Name: sales_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_orders (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    source_proforma_id uuid,
    converted_to_invoice_id uuid,
    so_number character varying(50) NOT NULL,
    order_date date NOT NULL,
    due_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    discount_total numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    amount_advanced numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_sales_orders_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'CONFIRMED'::character varying, 'DELIVERED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.sales_orders FORCE ROW LEVEL SECURITY;

--
-- Name: sales_return_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_return_lines (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    sales_return_id uuid NOT NULL,
    invoice_line_id uuid NOT NULL,
    product_id uuid,
    description character varying(255),
    quantity numeric(12,4) NOT NULL,
    rate numeric(15,4) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    hsn_sac character varying(8),
    gst_rate numeric(5,2) NOT NULL,
    cgst_rate numeric(5,2) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_rate numeric(5,2) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_rate numeric(5,2) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_rate numeric(5,2) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_rate numeric(5,2) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL
);

ALTER TABLE ONLY public.sales_return_lines FORCE ROW LEVEL SECURITY;

--
-- Name: sales_returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_returns (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    contact_id uuid,
    invoice_id uuid NOT NULL,
    return_number character varying(50) NOT NULL,
    issue_date date NOT NULL,
    status character varying(20) NOT NULL,
    subtotal numeric(15,4) NOT NULL,
    cgst_amount numeric(15,4) NOT NULL,
    sgst_amount numeric(15,4) NOT NULL,
    igst_amount numeric(15,4) NOT NULL,
    utgst_amount numeric(15,4) NOT NULL,
    cess_amount numeric(15,4) NOT NULL,
    round_off numeric(15,4) NOT NULL,
    total numeric(15,4) NOT NULL,
    pos_state_code character varying(2) NOT NULL,
    notes text,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    created_by uuid,
    replaces_id uuid,
    replaced_by_id uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_sales_returns_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'POSTED'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT ck_sales_returns_total_balance CHECK ((round(total, 2) = round(((((((subtotal + cgst_amount) + sgst_amount) + igst_amount) + utgst_amount) + cess_amount) + round_off), 2)))
);

ALTER TABLE ONLY public.sales_returns FORCE ROW LEVEL SECURITY;

--
-- Name: stock_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_ledger (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    warehouse_id uuid,
    quantity numeric(12,4) NOT NULL,
    balance_quantity numeric(12,4) NOT NULL,
    reference_type character varying(20) NOT NULL,
    reference_id uuid,
    rate numeric(15,4),
    created_at timestamp with time zone NOT NULL,
    created_by uuid,
    source_channel character varying(20),
    reverses_movement_id uuid,
    reversal_movement_id uuid,
    reversed_by uuid,
    reversed_at timestamp with time zone
);

ALTER TABLE ONLY public.stock_ledger FORCE ROW LEVEL SECURITY;

--
-- Name: sync_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sync_events (
    server_sequence bigint NOT NULL,
    event_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    device_id uuid NOT NULL,
    aggregate_type character varying(60) NOT NULL,
    aggregate_id uuid NOT NULL,
    event_type character varying(100) NOT NULL,
    event_version integer NOT NULL,
    payload json NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    received_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processed boolean NOT NULL,
    processing_error text
);

ALTER TABLE ONLY public.sync_events FORCE ROW LEVEL SECURITY;

--
-- Name: sync_events_server_sequence_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sync_events_server_sequence_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: sync_events_server_sequence_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sync_events_server_sequence_seq OWNED BY public.sync_events.server_sequence;

--
-- Name: tax_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_templates (
    id uuid NOT NULL,
    tenant_id uuid,
    name character varying(100) NOT NULL,
    rate numeric(5,2) NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.tax_templates FORCE ROW LEVEL SECURITY;

--
-- Name: tenant_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_invitations (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    email character varying(255) NOT NULL,
    role character varying(50) NOT NULL,
    invited_by uuid NOT NULL,
    token character varying(255) NOT NULL,
    status character varying(20) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_tenant_invitations_status CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'ACCEPTED'::character varying, 'EXPIRED'::character varying])::text[])))
);

ALTER TABLE ONLY public.tenant_invitations FORCE ROW LEVEL SECURITY;

--
-- Name: tenant_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_memberships (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying(50) NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

--
-- Name: tenant_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_settings (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(100),
    value character varying(255),
    logo_url character varying(255),
    currency character varying(10) NOT NULL,
    gst_enabled boolean NOT NULL,
    e_invoicing_enabled boolean NOT NULL,
    e_invoice_username character varying(100),
    e_invoice_password_hash character varying(255),
    e_way_bill_username character varying(100),
    e_way_bill_password_hash character varying(255),
    upi_id character varying(100),
    display_settings json NOT NULL,
    extra_settings json,
    origin_state_code character varying(2),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.tenant_settings FORCE ROW LEVEL SECURITY;

--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid NOT NULL,
    legal_name character varying(150) NOT NULL,
    trade_name character varying(150),
    gstin character varying(15),
    pan character varying(10),
    tax_mode character varying(20) DEFAULT 'NON_GST'::character varying NOT NULL,
    financial_year_start date NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone
);

--
-- Name: terms_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.terms_templates (
    id uuid NOT NULL,
    tenant_id uuid,
    name character varying(150) NOT NULL,
    content text NOT NULL,
    is_preset boolean NOT NULL,
    is_active boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

ALTER TABLE ONLY public.terms_templates FORCE ROW LEVEL SECURITY;

--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    transfer_number character varying(50),
    transfer_date date,
    from_warehouse_id uuid,
    from_warehouse_name character varying(200),
    to_warehouse_id uuid,
    to_warehouse_name character varying(200),
    status character varying(20) NOT NULL,
    lines json NOT NULL,
    notes text,
    completed_at timestamp with time zone,
    completed_by uuid,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_transfers_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'IN_TRANSIT'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::text[])))
);

ALTER TABLE ONLY public.transfers FORCE ROW LEVEL SECURITY;

--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(150) NOT NULL,
    phone_number character varying(15),
    is_active boolean NOT NULL,
    failed_login_attempts integer NOT NULL,
    locked_until timestamp with time zone,
    last_login_at timestamp with time zone,
    email_verified boolean NOT NULL,
    email_verify_token character varying(255),
    email_verify_expires timestamp with time zone,
    totp_secret character varying(32),
    totp_enabled boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    deleted_at timestamp with time zone
);

--
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_events (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    event_type character varying(100) NOT NULL,
    payload json NOT NULL,
    status character varying(20) NOT NULL,
    target_url character varying(512),
    retry_count integer NOT NULL,
    max_retries integer NOT NULL,
    last_error text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_webhook_events_status CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'DELIVERED'::character varying, 'FAILED'::character varying])::text[])))
);

ALTER TABLE ONLY public.webhook_events FORCE ROW LEVEL SECURITY;

--
-- Name: sync_events server_sequence; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_events ALTER COLUMN server_sequence SET DEFAULT nextval('public.sync_events_server_sequence_seq'::regclass);

--
-- Name: accounting_periods accounting_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_periods
    ADD CONSTRAINT accounting_periods_pkey PRIMARY KEY (id);

--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);

--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);

--
-- Name: bank_reconciliations bank_reconciliations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_reconciliations
    ADD CONSTRAINT bank_reconciliations_pkey PRIMARY KEY (id);

--
-- Name: bank_statements bank_statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_statements
    ADD CONSTRAINT bank_statements_pkey PRIMARY KEY (id);

--
-- Name: bank_transactions bank_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_transactions
    ADD CONSTRAINT bank_transactions_pkey PRIMARY KEY (id);

--
-- Name: banking_profiles banking_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banking_profiles
    ADD CONSTRAINT banking_profiles_pkey PRIMARY KEY (id);

--
-- Name: bill_lines bill_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_lines
    ADD CONSTRAINT bill_lines_pkey PRIMARY KEY (id);

--
-- Name: bill_payment_allocations bill_payment_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payment_allocations
    ADD CONSTRAINT bill_payment_allocations_pkey PRIMARY KEY (id);

--
-- Name: bill_payments bill_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payments
    ADD CONSTRAINT bill_payments_pkey PRIMARY KEY (id);

--
-- Name: bills bills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_pkey PRIMARY KEY (id);

--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);

--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);

--
-- Name: credit_note_lines credit_note_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_lines
    ADD CONSTRAINT credit_note_lines_pkey PRIMARY KEY (id);

--
-- Name: credit_notes credit_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_pkey PRIMARY KEY (id);

--
-- Name: debit_note_lines debit_note_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.debit_note_lines
    ADD CONSTRAINT debit_note_lines_pkey PRIMARY KEY (id);

--
-- Name: debit_notes debit_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.debit_notes
    ADD CONSTRAINT debit_notes_pkey PRIMARY KEY (id);

--
-- Name: delivery_challan_lines delivery_challan_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challan_lines
    ADD CONSTRAINT delivery_challan_lines_pkey PRIMARY KEY (id);

--
-- Name: delivery_challans delivery_challans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challans
    ADD CONSTRAINT delivery_challans_pkey PRIMARY KEY (id);

--
-- Name: eway_bills eway_bills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eway_bills
    ADD CONSTRAINT eway_bills_pkey PRIMARY KEY (id);

--
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);

--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);

--
-- Name: financial_year_audits financial_year_audits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_year_audits
    ADD CONSTRAINT financial_year_audits_pkey PRIMARY KEY (id);

--
-- Name: financial_years financial_years_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_years
    ADD CONSTRAINT financial_years_pkey PRIMARY KEY (id);

--
-- Name: goods_receipt_lines goods_receipt_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT goods_receipt_lines_pkey PRIMARY KEY (id);

--
-- Name: goods_receipts goods_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT goods_receipts_pkey PRIMARY KEY (id);

--
-- Name: gst_returns gst_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gst_returns
    ADD CONSTRAINT gst_returns_pkey PRIMARY KEY (id);

--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);

--
-- Name: integration_connections integration_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_connections
    ADD CONSTRAINT integration_connections_pkey PRIMARY KEY (id);

--
-- Name: integration_dead_letter integration_dead_letter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_dead_letter
    ADD CONSTRAINT integration_dead_letter_pkey PRIMARY KEY (id);

--
-- Name: integration_entity_map integration_entity_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_entity_map
    ADD CONSTRAINT integration_entity_map_pkey PRIMARY KEY (id);

--
-- Name: integration_event_log integration_event_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_event_log
    ADD CONSTRAINT integration_event_log_pkey PRIMARY KEY (id);

--
-- Name: integration_inventory_movement integration_inventory_movement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_inventory_movement
    ADD CONSTRAINT integration_inventory_movement_pkey PRIMARY KEY (id);

--
-- Name: integration_invoice_line_map integration_invoice_line_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_invoice_line_map
    ADD CONSTRAINT integration_invoice_line_map_pkey PRIMARY KEY (id);

--
-- Name: integration_master_sync_audit integration_master_sync_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_master_sync_audit
    ADD CONSTRAINT integration_master_sync_audit_pkey PRIMARY KEY (id);

--
-- Name: integration_order_audit integration_order_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_audit
    ADD CONSTRAINT integration_order_audit_pkey PRIMARY KEY (id);

--
-- Name: integration_order_state integration_order_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_state
    ADD CONSTRAINT integration_order_state_pkey PRIMARY KEY (id);

--
-- Name: integration_payment_audit integration_payment_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_audit
    ADD CONSTRAINT integration_payment_audit_pkey PRIMARY KEY (id);

--
-- Name: integration_payment_inventory_movement integration_payment_inventory_movement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_inventory_movement
    ADD CONSTRAINT integration_payment_inventory_movement_pkey PRIMARY KEY (id);

--
-- Name: integration_payment_state integration_payment_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT integration_payment_state_pkey PRIMARY KEY (id);

--
-- Name: integration_replay_cache integration_replay_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_replay_cache
    ADD CONSTRAINT integration_replay_cache_pkey PRIMARY KEY (id);

--
-- Name: integration_synced_customers integration_synced_customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_customers
    ADD CONSTRAINT integration_synced_customers_pkey PRIMARY KEY (id);

--
-- Name: integration_synced_inventory_levels integration_synced_inventory_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_inventory_levels
    ADD CONSTRAINT integration_synced_inventory_levels_pkey PRIMARY KEY (id);

--
-- Name: integration_synced_prices integration_synced_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_prices
    ADD CONSTRAINT integration_synced_prices_pkey PRIMARY KEY (id);

--
-- Name: integration_synced_product_variants integration_synced_product_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_product_variants
    ADD CONSTRAINT integration_synced_product_variants_pkey PRIMARY KEY (id);

--
-- Name: integration_synced_products integration_synced_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_products
    ADD CONSTRAINT integration_synced_products_pkey PRIMARY KEY (id);

--
-- Name: inventory_adjustment_lines inventory_adjustment_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_lines
    ADD CONSTRAINT inventory_adjustment_lines_pkey PRIMARY KEY (id);

--
-- Name: inventory_adjustments inventory_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustments
    ADD CONSTRAINT inventory_adjustments_pkey PRIMARY KEY (id);

--
-- Name: inventory_carry_forwards inventory_carry_forwards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_carry_forwards
    ADD CONSTRAINT inventory_carry_forwards_pkey PRIMARY KEY (id);

--
-- Name: invoice_lines invoice_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_lines
    ADD CONSTRAINT invoice_lines_pkey PRIMARY KEY (id);

--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);

--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);

--
-- Name: journal_lines journal_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_pkey PRIMARY KEY (id);

--
-- Name: numbering_series numbering_series_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.numbering_series
    ADD CONSTRAINT numbering_series_pkey PRIMARY KEY (id);

--
-- Name: offline_number_allocations offline_number_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_number_allocations
    ADD CONSTRAINT offline_number_allocations_pkey PRIMARY KEY (id);

--
-- Name: opening_balance_snapshots opening_balance_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opening_balance_snapshots
    ADD CONSTRAINT opening_balance_snapshots_pkey PRIMARY KEY (id);

--
-- Name: password_reset_tokens password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey PRIMARY KEY (id);

--
-- Name: payment_allocations payment_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_pkey PRIMARY KEY (id);

--
-- Name: payment_terms payment_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_terms
    ADD CONSTRAINT payment_terms_pkey PRIMARY KEY (id);

--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);

--
-- Name: period_lock_audits period_lock_audits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_lock_audits
    ADD CONSTRAINT period_lock_audits_pkey PRIMARY KEY (id);

--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);

--
-- Name: proforma_invoice_lines proforma_invoice_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoice_lines
    ADD CONSTRAINT proforma_invoice_lines_pkey PRIMARY KEY (id);

--
-- Name: proforma_invoices proforma_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoices
    ADD CONSTRAINT proforma_invoices_pkey PRIMARY KEY (id);

--
-- Name: purchase_order_lines purchase_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT purchase_order_lines_pkey PRIMARY KEY (id);

--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);

--
-- Name: purchase_return_lines purchase_return_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_return_lines
    ADD CONSTRAINT purchase_return_lines_pkey PRIMARY KEY (id);

--
-- Name: purchase_returns purchase_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_returns
    ADD CONSTRAINT purchase_returns_pkey PRIMARY KEY (id);

--
-- Name: recurring_invoice_items recurring_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_invoice_items
    ADD CONSTRAINT recurring_invoice_items_pkey PRIMARY KEY (id);

--
-- Name: recurring_invoices recurring_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_invoices
    ADD CONSTRAINT recurring_invoices_pkey PRIMARY KEY (id);

--
-- Name: sales_order_lines sales_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT sales_order_lines_pkey PRIMARY KEY (id);

--
-- Name: sales_orders sales_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_pkey PRIMARY KEY (id);

--
-- Name: sales_return_lines sales_return_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_return_lines
    ADD CONSTRAINT sales_return_lines_pkey PRIMARY KEY (id);

--
-- Name: sales_returns sales_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_returns
    ADD CONSTRAINT sales_returns_pkey PRIMARY KEY (id);

--
-- Name: stock_ledger stock_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_pkey PRIMARY KEY (id);

--
-- Name: sync_events sync_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_events
    ADD CONSTRAINT sync_events_pkey PRIMARY KEY (server_sequence);

--
-- Name: tax_templates tax_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_templates
    ADD CONSTRAINT tax_templates_pkey PRIMARY KEY (id);

--
-- Name: tenant_invitations tenant_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_invitations
    ADD CONSTRAINT tenant_invitations_pkey PRIMARY KEY (id);

--
-- Name: tenant_invitations tenant_invitations_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_invitations
    ADD CONSTRAINT tenant_invitations_token_key UNIQUE (token);

--
-- Name: tenant_memberships tenant_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_pkey PRIMARY KEY (id);

--
-- Name: tenant_settings tenant_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_settings
    ADD CONSTRAINT tenant_settings_pkey PRIMARY KEY (id);

--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);

--
-- Name: terms_templates terms_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms_templates
    ADD CONSTRAINT terms_templates_pkey PRIMARY KEY (id);

--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (id);

--
-- Name: accounts uq_account_tenant_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT uq_account_tenant_code UNIQUE (tenant_id, code);

--
-- Name: accounting_periods uq_accounting_periods_tenant_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounting_periods
    ADD CONSTRAINT uq_accounting_periods_tenant_name UNIQUE (tenant_id, period_name);

--
-- Name: bill_payments uq_bill_payments_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payments
    ADD CONSTRAINT uq_bill_payments_tenant_number UNIQUE (tenant_id, payment_number);

--
-- Name: bills uq_bills_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT uq_bills_tenant_number UNIQUE (tenant_id, bill_number);

--
-- Name: credit_notes uq_credit_notes_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT uq_credit_notes_tenant_number UNIQUE (tenant_id, credit_note_number);

--
-- Name: debit_notes uq_debit_notes_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.debit_notes
    ADD CONSTRAINT uq_debit_notes_tenant_number UNIQUE (tenant_id, debit_note_number);

--
-- Name: delivery_challans uq_delivery_challans_challan_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challans
    ADD CONSTRAINT uq_delivery_challans_challan_number UNIQUE (tenant_id, challan_number);

--
-- Name: eway_bills uq_eway_bill_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eway_bills
    ADD CONSTRAINT uq_eway_bill_number UNIQUE (eway_bill_number);

--
-- Name: expenses uq_expenses_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT uq_expenses_tenant_number UNIQUE (tenant_id, expense_number);

--
-- Name: financial_years uq_financial_years_tenant_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_years
    ADD CONSTRAINT uq_financial_years_tenant_name UNIQUE (tenant_id, name);

--
-- Name: goods_receipts uq_goods_receipts_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT uq_goods_receipts_tenant_number UNIQUE (tenant_id, receipt_number);

--
-- Name: gst_returns uq_gst_return_period; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gst_returns
    ADD CONSTRAINT uq_gst_return_period UNIQUE (tenant_id, return_type, period_start);

--
-- Name: idempotency_keys uq_idempotency_key_tenant_method_path; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT uq_idempotency_key_tenant_method_path UNIQUE (idempotency_key, tenant_id, method, path);

--
-- Name: integration_connections uq_integration_connection_external_tenant; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_connections
    ADD CONSTRAINT uq_integration_connection_external_tenant UNIQUE (integration_name, external_tenant_id);

--
-- Name: integration_entity_map uq_integration_entity_map_external; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_entity_map
    ADD CONSTRAINT uq_integration_entity_map_external UNIQUE (tenant_id, integration_name, entity_type, external_id);

--
-- Name: integration_entity_map uq_integration_entity_map_internal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_entity_map
    ADD CONSTRAINT uq_integration_entity_map_internal UNIQUE (tenant_id, integration_name, entity_type, internal_id);

--
-- Name: integration_event_log uq_integration_event_log_request_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_event_log
    ADD CONSTRAINT uq_integration_event_log_request_id UNIQUE (request_id);

--
-- Name: integration_invoice_line_map uq_integration_invoice_line_apexbooks; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_invoice_line_map
    ADD CONSTRAINT uq_integration_invoice_line_apexbooks UNIQUE (tenant_id, apexbooks_invoice_line_id);

--
-- Name: integration_invoice_line_map uq_integration_invoice_line_medusa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_invoice_line_map
    ADD CONSTRAINT uq_integration_invoice_line_medusa UNIQUE (tenant_id, invoice_id, medusa_line_id);

--
-- Name: integration_order_state uq_integration_order_apexbooks; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_state
    ADD CONSTRAINT uq_integration_order_apexbooks UNIQUE (tenant_id, apexbooks_order_id);

--
-- Name: integration_order_state uq_integration_order_medusa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_state
    ADD CONSTRAINT uq_integration_order_medusa UNIQUE (tenant_id, medusa_order_id);

--
-- Name: integration_order_state uq_integration_order_sales_order; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_state
    ADD CONSTRAINT uq_integration_order_sales_order UNIQUE (sales_order_id);

--
-- Name: integration_payment_state uq_integration_payment_medusa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT uq_integration_payment_medusa UNIQUE (tenant_id, medusa_payment_id);

--
-- Name: integration_payment_state uq_integration_payment_receipt; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT uq_integration_payment_receipt UNIQUE (payment_id);

--
-- Name: integration_payment_state uq_integration_payment_sequence; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT uq_integration_payment_sequence UNIQUE (tenant_id, order_state_id, capture_sequence);

--
-- Name: integration_payment_state uq_integration_payment_transaction; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT uq_integration_payment_transaction UNIQUE (tenant_id, provider_id, transaction_id);

--
-- Name: integration_replay_cache uq_integration_replay_event; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_replay_cache
    ADD CONSTRAINT uq_integration_replay_event UNIQUE (tenant_id, integration_name, event_id);

--
-- Name: integration_replay_cache uq_integration_replay_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_replay_cache
    ADD CONSTRAINT uq_integration_replay_idempotency UNIQUE (tenant_id, integration_name, idempotency_key);

--
-- Name: inventory_adjustments uq_inventory_adjustments_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustments
    ADD CONSTRAINT uq_inventory_adjustments_tenant_number UNIQUE (tenant_id, adjustment_number);

--
-- Name: invoices uq_invoices_irn; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT uq_invoices_irn UNIQUE (irn);

--
-- Name: invoices uq_invoices_source_document; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT uq_invoices_source_document UNIQUE (tenant_id, source_document_type, source_document_id);

--
-- Name: invoices uq_invoices_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT uq_invoices_tenant_number UNIQUE (tenant_id, invoice_number);

--
-- Name: journal_entries uq_journal_entries_tenant_reference; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT uq_journal_entries_tenant_reference UNIQUE (tenant_id, reference_number);

--
-- Name: journal_entries uq_journal_entries_tenant_source; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT uq_journal_entries_tenant_source UNIQUE (tenant_id, source_type, source_id);

--
-- Name: tenant_memberships uq_membership_tenant_user; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT uq_membership_tenant_user UNIQUE (tenant_id, user_id);

--
-- Name: offline_number_allocations uq_offline_number_allocation_start; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_number_allocations
    ADD CONSTRAINT uq_offline_number_allocation_start UNIQUE (tenant_id, document_type, range_start);

--
-- Name: payment_allocations uq_payment_allocations_payment_invoice; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT uq_payment_allocations_payment_invoice UNIQUE (payment_id, invoice_id);

--
-- Name: payments uq_payments_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uq_payments_tenant_number UNIQUE (tenant_id, payment_number);

--
-- Name: proforma_invoices uq_proforma_invoices_proforma_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoices
    ADD CONSTRAINT uq_proforma_invoices_proforma_number UNIQUE (tenant_id, proforma_number);

--
-- Name: purchase_orders uq_purchase_orders_po_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT uq_purchase_orders_po_number UNIQUE (tenant_id, po_number);

--
-- Name: purchase_returns uq_purchase_returns_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_returns
    ADD CONSTRAINT uq_purchase_returns_tenant_number UNIQUE (tenant_id, return_number);

--
-- Name: sales_orders uq_sales_orders_so_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT uq_sales_orders_so_number UNIQUE (tenant_id, so_number);

--
-- Name: sales_returns uq_sales_returns_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_returns
    ADD CONSTRAINT uq_sales_returns_tenant_number UNIQUE (tenant_id, return_number);

--
-- Name: sync_events uq_sync_event_tenant_event; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_events
    ADD CONSTRAINT uq_sync_event_tenant_event UNIQUE (tenant_id, event_id);

--
-- Name: integration_synced_customers uq_synced_customer_external; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_customers
    ADD CONSTRAINT uq_synced_customer_external UNIQUE (tenant_id, apexbooks_customer_id);

--
-- Name: integration_synced_customers uq_synced_customer_medusa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_customers
    ADD CONSTRAINT uq_synced_customer_medusa UNIQUE (tenant_id, medusa_customer_id);

--
-- Name: integration_synced_inventory_levels uq_synced_inventory_scope; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_inventory_levels
    ADD CONSTRAINT uq_synced_inventory_scope UNIQUE (tenant_id, variant_id, warehouse_id);

--
-- Name: integration_synced_products uq_synced_product_external; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_products
    ADD CONSTRAINT uq_synced_product_external UNIQUE (tenant_id, apexbooks_product_id);

--
-- Name: integration_synced_products uq_synced_product_medusa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_products
    ADD CONSTRAINT uq_synced_product_medusa UNIQUE (tenant_id, medusa_product_id);

--
-- Name: integration_synced_product_variants uq_synced_variant_external; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_product_variants
    ADD CONSTRAINT uq_synced_variant_external UNIQUE (tenant_id, apexbooks_variant_id);

--
-- Name: integration_synced_product_variants uq_synced_variant_medusa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_product_variants
    ADD CONSTRAINT uq_synced_variant_medusa UNIQUE (tenant_id, medusa_variant_id);

--
-- Name: tenants uq_tenants_gstin; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT uq_tenants_gstin UNIQUE (gstin);

--
-- Name: transfers uq_transfers_tenant_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT uq_transfers_tenant_number UNIQUE (tenant_id, transfer_number);

--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);

--
-- Name: ix_accounting_periods_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_accounting_periods_tenant ON public.accounting_periods USING btree (tenant_id);

--
-- Name: ix_accounts_tenant_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_accounts_tenant_type ON public.accounts USING btree (tenant_id, account_type);

--
-- Name: ix_audit_logs_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_logs_actor ON public.audit_logs USING btree (tenant_id, actor_id);

--
-- Name: ix_audit_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_logs_entity ON public.audit_logs USING btree (tenant_id, entity_type, entity_id);

--
-- Name: ix_audit_logs_tenant_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_audit_logs_tenant_timestamp ON public.audit_logs USING btree (tenant_id, "timestamp");

--
-- Name: ix_bank_reconciliations_bill_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_reconciliations_bill_payment_id ON public.bank_reconciliations USING btree (bill_payment_id);

--
-- Name: ix_bank_reconciliations_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_reconciliations_payment_id ON public.bank_reconciliations USING btree (payment_id);

--
-- Name: ix_bank_reconciliations_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_reconciliations_transaction_id ON public.bank_reconciliations USING btree (bank_transaction_id);

--
-- Name: ix_bank_statements_banking_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_statements_banking_profile ON public.bank_statements USING btree (tenant_id, banking_profile_id);

--
-- Name: ix_bank_statements_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_statements_tenant_date ON public.bank_statements USING btree (tenant_id, statement_date);

--
-- Name: ix_bank_transactions_amount; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_transactions_amount ON public.bank_transactions USING btree (bank_statement_id, amount);

--
-- Name: ix_bank_transactions_statement_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bank_transactions_statement_date ON public.bank_transactions USING btree (bank_statement_id, transaction_date);

--
-- Name: ix_bill_lines_bill_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bill_lines_bill_id ON public.bill_lines USING btree (bill_id);

--
-- Name: ix_bill_payment_allocations_bill_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bill_payment_allocations_bill_id ON public.bill_payment_allocations USING btree (bill_id);

--
-- Name: ix_bill_payment_allocations_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bill_payment_allocations_payment_id ON public.bill_payment_allocations USING btree (payment_id);

--
-- Name: ix_bill_payment_allocations_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bill_payment_allocations_tenant ON public.bill_payment_allocations USING btree (tenant_id);

--
-- Name: ix_bill_payments_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bill_payments_tenant_date ON public.bill_payments USING btree (tenant_id, payment_date);

--
-- Name: ix_bill_payments_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bill_payments_tenant_deleted ON public.bill_payments USING btree (tenant_id, deleted_at);

--
-- Name: ix_bills_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bills_due_date ON public.bills USING btree (tenant_id, due_date);

--
-- Name: ix_bills_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bills_tenant_contact ON public.bills USING btree (tenant_id, contact_id);

--
-- Name: ix_bills_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bills_tenant_date_status ON public.bills USING btree (tenant_id, issue_date, status);

--
-- Name: ix_bills_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bills_tenant_deleted ON public.bills USING btree (tenant_id, deleted_at);

--
-- Name: ix_branches_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_branches_tenant_deleted ON public.branches USING btree (tenant_id, deleted_at);

--
-- Name: ix_contacts_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_contacts_tenant_deleted ON public.contacts USING btree (tenant_id, deleted_at);

--
-- Name: ix_contacts_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_contacts_tenant_id ON public.contacts USING btree (tenant_id);

--
-- Name: ix_contacts_tenant_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_contacts_tenant_type ON public.contacts USING btree (tenant_id, contact_type);

--
-- Name: ix_credit_notes_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_credit_notes_invoice_id ON public.credit_notes USING btree (invoice_id);

--
-- Name: ix_credit_notes_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_credit_notes_tenant_deleted ON public.credit_notes USING btree (tenant_id, deleted_at);

--
-- Name: ix_credit_notes_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_credit_notes_tenant_id ON public.credit_notes USING btree (tenant_id);

--
-- Name: ix_debit_notes_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_debit_notes_invoice_id ON public.debit_notes USING btree (invoice_id);

--
-- Name: ix_debit_notes_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_debit_notes_tenant_deleted ON public.debit_notes USING btree (tenant_id, deleted_at);

--
-- Name: ix_debit_notes_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_debit_notes_tenant_id ON public.debit_notes USING btree (tenant_id);

--
-- Name: ix_delivery_challan_lines_dc_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_delivery_challan_lines_dc_id ON public.delivery_challan_lines USING btree (delivery_challan_id);

--
-- Name: ix_delivery_challans_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_delivery_challans_due_date ON public.delivery_challans USING btree (tenant_id, due_date);

--
-- Name: ix_delivery_challans_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_delivery_challans_tenant_contact ON public.delivery_challans USING btree (tenant_id, contact_id);

--
-- Name: ix_delivery_challans_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_delivery_challans_tenant_date_status ON public.delivery_challans USING btree (tenant_id, challan_date, status);

--
-- Name: ix_delivery_challans_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_delivery_challans_tenant_deleted ON public.delivery_challans USING btree (tenant_id, deleted_at);

--
-- Name: ix_eway_bills_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_eway_bills_tenant_id ON public.eway_bills USING btree (tenant_id);

--
-- Name: ix_expenses_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_expenses_tenant_date ON public.expenses USING btree (tenant_id, expense_date);

--
-- Name: ix_expenses_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_expenses_tenant_deleted ON public.expenses USING btree (tenant_id, deleted_at);

--
-- Name: ix_financial_years_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_financial_years_tenant ON public.financial_years USING btree (tenant_id);

--
-- Name: ix_fy_audits_fy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_fy_audits_fy ON public.financial_year_audits USING btree (financial_year_id);

--
-- Name: ix_fy_audits_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_fy_audits_tenant ON public.financial_year_audits USING btree (tenant_id);

--
-- Name: ix_goods_receipt_lines_receipt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_goods_receipt_lines_receipt ON public.goods_receipt_lines USING btree (goods_receipt_id);

--
-- Name: ix_goods_receipts_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_goods_receipts_tenant_date ON public.goods_receipts USING btree (tenant_id, receipt_date);

--
-- Name: ix_goods_receipts_tenant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_goods_receipts_tenant_status ON public.goods_receipts USING btree (tenant_id, status);

--
-- Name: ix_gst_returns_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_gst_returns_tenant ON public.gst_returns USING btree (tenant_id, return_type);

--
-- Name: ix_icf_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_icf_product ON public.inventory_carry_forwards USING btree (product_id);

--
-- Name: ix_icf_tenant_fy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_icf_tenant_fy ON public.inventory_carry_forwards USING btree (tenant_id, financial_year_id);

--
-- Name: ix_idempotency_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_idempotency_created ON public.idempotency_keys USING btree (created_at);

--
-- Name: ix_integration_connections_api_key_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_connections_api_key_hash ON public.integration_connections USING btree (api_key_hash);

--
-- Name: ix_integration_connections_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_connections_tenant ON public.integration_connections USING btree (tenant_id, integration_name);

--
-- Name: ix_integration_dead_letter_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_dead_letter_status_created ON public.integration_dead_letter USING btree (status, created_at);

--
-- Name: ix_integration_dead_letter_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_dead_letter_tenant ON public.integration_dead_letter USING btree (tenant_id, integration_name);

--
-- Name: ix_integration_entity_map_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_entity_map_lookup ON public.integration_entity_map USING btree (tenant_id, integration_name, entity_type);

--
-- Name: ix_integration_event_log_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_event_log_idempotency ON public.integration_event_log USING btree (integration_name, idempotency_key);

--
-- Name: ix_integration_event_log_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_event_log_status_created ON public.integration_event_log USING btree (status, created_at);

--
-- Name: ix_integration_event_log_tenant_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_event_log_tenant_event ON public.integration_event_log USING btree (tenant_id, event_id);

--
-- Name: ix_integration_inventory_movement_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_inventory_movement_level ON public.integration_inventory_movement USING btree (tenant_id, variant_id, warehouse_id);

--
-- Name: ix_integration_inventory_movement_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_inventory_movement_order ON public.integration_inventory_movement USING btree (tenant_id, order_state_id);

--
-- Name: ix_integration_order_audit_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_order_audit_event ON public.integration_order_audit USING btree (tenant_id, event_id);

--
-- Name: ix_integration_order_audit_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_order_audit_order ON public.integration_order_audit USING btree (tenant_id, medusa_order_id);

--
-- Name: ix_integration_order_tenant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_order_tenant_status ON public.integration_order_state USING btree (tenant_id, status);

--
-- Name: ix_integration_payment_audit_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_payment_audit_event ON public.integration_payment_audit USING btree (tenant_id, event_id);

--
-- Name: ix_integration_payment_audit_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_payment_audit_order ON public.integration_payment_audit USING btree (tenant_id, medusa_order_id);

--
-- Name: ix_integration_payment_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_payment_order ON public.integration_payment_state USING btree (tenant_id, order_state_id);

--
-- Name: ix_integration_replay_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_integration_replay_expires ON public.integration_replay_cache USING btree (expires_at);

--
-- Name: ix_inventory_adjustments_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inventory_adjustments_tenant_date ON public.inventory_adjustments USING btree (tenant_id, adjustment_date);

--
-- Name: ix_invoice_lines_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invoice_lines_invoice_id ON public.invoice_lines USING btree (invoice_id);

--
-- Name: ix_invoice_lines_invoice_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invoice_lines_invoice_product ON public.invoice_lines USING btree (invoice_id, product_id);

--
-- Name: ix_invoices_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invoices_due_date ON public.invoices USING btree (tenant_id, due_date);

--
-- Name: ix_invoices_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invoices_tenant_contact ON public.invoices USING btree (tenant_id, contact_id);

--
-- Name: ix_invoices_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invoices_tenant_date_status ON public.invoices USING btree (tenant_id, issue_date, status);

--
-- Name: ix_invoices_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invoices_tenant_deleted ON public.invoices USING btree (tenant_id, deleted_at);

--
-- Name: ix_journal_entries_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_journal_entries_source ON public.journal_entries USING btree (tenant_id, source_type, source_id);

--
-- Name: ix_journal_entries_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_journal_entries_tenant_date ON public.journal_entries USING btree (tenant_id, entry_date);

--
-- Name: ix_journal_lines_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_journal_lines_account_id ON public.journal_lines USING btree (account_id);

--
-- Name: ix_journal_lines_entry_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_journal_lines_entry_account ON public.journal_lines USING btree (entry_id, account_id);

--
-- Name: ix_journal_lines_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_journal_lines_entry_id ON public.journal_lines USING btree (entry_id);

--
-- Name: ix_master_sync_audit_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_master_sync_audit_entity ON public.integration_master_sync_audit USING btree (tenant_id, entity_type, external_id);

--
-- Name: ix_master_sync_audit_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_master_sync_audit_event ON public.integration_master_sync_audit USING btree (tenant_id, event_id);

--
-- Name: ix_ob_snapshots_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ob_snapshots_account ON public.opening_balance_snapshots USING btree (account_id);

--
-- Name: ix_ob_snapshots_tenant_fy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ob_snapshots_tenant_fy ON public.opening_balance_snapshots USING btree (tenant_id, financial_year_id);

--
-- Name: ix_offline_number_allocations_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_offline_number_allocations_device ON public.offline_number_allocations USING btree (tenant_id, device_id, document_type);

--
-- Name: ix_password_reset_tokens_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_password_reset_tokens_token ON public.password_reset_tokens USING btree (token);

--
-- Name: ix_payment_allocations_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payment_allocations_invoice_id ON public.payment_allocations USING btree (invoice_id);

--
-- Name: ix_payment_allocations_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payment_allocations_payment_id ON public.payment_allocations USING btree (payment_id);

--
-- Name: ix_payment_allocations_payment_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payment_allocations_payment_invoice ON public.payment_allocations USING btree (payment_id, invoice_id);

--
-- Name: ix_payment_allocations_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payment_allocations_tenant ON public.payment_allocations USING btree (tenant_id);

--
-- Name: ix_payment_inventory_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payment_inventory_level ON public.integration_payment_inventory_movement USING btree (tenant_id, variant_id, warehouse_id);

--
-- Name: ix_payment_inventory_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payment_inventory_order ON public.integration_payment_inventory_movement USING btree (tenant_id, order_state_id);

--
-- Name: ix_payments_tenant_contact_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payments_tenant_contact_date ON public.payments USING btree (tenant_id, contact_id, payment_date);

--
-- Name: ix_payments_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payments_tenant_date ON public.payments USING btree (tenant_id, payment_date);

--
-- Name: ix_payments_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payments_tenant_deleted ON public.payments USING btree (tenant_id, deleted_at);

--
-- Name: ix_payments_tenant_status_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_payments_tenant_status_date ON public.payments USING btree (tenant_id, status, payment_date);

--
-- Name: ix_pla_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pla_tenant_date ON public.period_lock_audits USING btree (tenant_id, period_date);

--
-- Name: ix_products_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_products_tenant_deleted ON public.products USING btree (tenant_id, deleted_at);

--
-- Name: ix_products_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_products_tenant_id ON public.products USING btree (tenant_id);

--
-- Name: ix_proforma_invoice_lines_pi_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_proforma_invoice_lines_pi_id ON public.proforma_invoice_lines USING btree (proforma_invoice_id);

--
-- Name: ix_proforma_invoices_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_proforma_invoices_due_date ON public.proforma_invoices USING btree (tenant_id, due_date);

--
-- Name: ix_proforma_invoices_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_proforma_invoices_tenant_contact ON public.proforma_invoices USING btree (tenant_id, contact_id);

--
-- Name: ix_proforma_invoices_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_proforma_invoices_tenant_date_status ON public.proforma_invoices USING btree (tenant_id, issue_date, status);

--
-- Name: ix_proforma_invoices_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_proforma_invoices_tenant_deleted ON public.proforma_invoices USING btree (tenant_id, deleted_at);

--
-- Name: ix_purchase_order_lines_po_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_order_lines_po_id ON public.purchase_order_lines USING btree (purchase_order_id);

--
-- Name: ix_purchase_orders_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_orders_due_date ON public.purchase_orders USING btree (tenant_id, due_date);

--
-- Name: ix_purchase_orders_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_orders_tenant_contact ON public.purchase_orders USING btree (tenant_id, contact_id);

--
-- Name: ix_purchase_orders_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_orders_tenant_date_status ON public.purchase_orders USING btree (tenant_id, order_date, status);

--
-- Name: ix_purchase_orders_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_orders_tenant_deleted ON public.purchase_orders USING btree (tenant_id, deleted_at);

--
-- Name: ix_purchase_returns_bill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_returns_bill ON public.purchase_returns USING btree (tenant_id, bill_id);

--
-- Name: ix_purchase_returns_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_returns_tenant_contact ON public.purchase_returns USING btree (tenant_id, contact_id);

--
-- Name: ix_purchase_returns_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_returns_tenant_date_status ON public.purchase_returns USING btree (tenant_id, issue_date, status);

--
-- Name: ix_purchase_returns_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_purchase_returns_tenant_deleted ON public.purchase_returns USING btree (tenant_id, deleted_at);

--
-- Name: ix_recurring_invoice_items_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_recurring_invoice_items_template_id ON public.recurring_invoice_items USING btree (recurring_invoice_id);

--
-- Name: ix_recurring_invoices_next_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_recurring_invoices_next_date ON public.recurring_invoices USING btree (next_date);

--
-- Name: ix_recurring_invoices_tenant_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_recurring_invoices_tenant_active ON public.recurring_invoices USING btree (tenant_id, is_active);

--
-- Name: ix_sales_order_lines_so_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_order_lines_so_id ON public.sales_order_lines USING btree (sales_order_id);

--
-- Name: ix_sales_orders_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_orders_due_date ON public.sales_orders USING btree (tenant_id, due_date);

--
-- Name: ix_sales_orders_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_orders_tenant_contact ON public.sales_orders USING btree (tenant_id, contact_id);

--
-- Name: ix_sales_orders_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_orders_tenant_date_status ON public.sales_orders USING btree (tenant_id, order_date, status);

--
-- Name: ix_sales_orders_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_orders_tenant_deleted ON public.sales_orders USING btree (tenant_id, deleted_at);

--
-- Name: ix_sales_returns_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_returns_invoice ON public.sales_returns USING btree (tenant_id, invoice_id);

--
-- Name: ix_sales_returns_tenant_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_returns_tenant_contact ON public.sales_returns USING btree (tenant_id, contact_id);

--
-- Name: ix_sales_returns_tenant_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_returns_tenant_date_status ON public.sales_returns USING btree (tenant_id, issue_date, status);

--
-- Name: ix_sales_returns_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sales_returns_tenant_deleted ON public.sales_returns USING btree (tenant_id, deleted_at);

--
-- Name: ix_stock_ledger_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_stock_ledger_tenant_date ON public.stock_ledger USING btree (tenant_id, created_at);

--
-- Name: ix_stock_ledger_tenant_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_stock_ledger_tenant_product ON public.stock_ledger USING btree (tenant_id, product_id);

--
-- Name: ix_stock_ledger_tenant_warehouse_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_stock_ledger_tenant_warehouse_product ON public.stock_ledger USING btree (tenant_id, warehouse_id, product_id);

--
-- Name: ix_sync_events_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sync_events_tenant_id ON public.sync_events USING btree (tenant_id);

--
-- Name: ix_sync_pull; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sync_pull ON public.sync_events USING btree (tenant_id, server_sequence);

--
-- Name: ix_sync_tenant_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sync_tenant_event_type ON public.sync_events USING btree (tenant_id, event_type);

--
-- Name: ix_sync_tenant_processed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_sync_tenant_processed ON public.sync_events USING btree (tenant_id, processed);

--
-- Name: ix_synced_customers_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_synced_customers_tenant ON public.integration_synced_customers USING btree (tenant_id);

--
-- Name: ix_synced_inventory_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_synced_inventory_product ON public.integration_synced_inventory_levels USING btree (tenant_id, product_id);

--
-- Name: ix_synced_prices_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_synced_prices_product ON public.integration_synced_prices USING btree (tenant_id, product_id);

--
-- Name: ix_synced_products_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_synced_products_tenant ON public.integration_synced_products USING btree (tenant_id);

--
-- Name: ix_synced_variants_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_synced_variants_product ON public.integration_synced_product_variants USING btree (product_id);

--
-- Name: ix_tenant_invitations_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tenant_invitations_email ON public.tenant_invitations USING btree (tenant_id, email);

--
-- Name: ix_terms_templates_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_terms_templates_tenant ON public.terms_templates USING btree (tenant_id);

--
-- Name: ix_transfers_tenant_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_transfers_tenant_date ON public.transfers USING btree (tenant_id, transfer_date);

--
-- Name: ix_transfers_tenant_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_transfers_tenant_deleted ON public.transfers USING btree (tenant_id, deleted_at);

--
-- Name: ix_transfers_tenant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_transfers_tenant_status ON public.transfers USING btree (tenant_id, status);

--
-- Name: ix_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_users_email ON public.users USING btree (email);

--
-- Name: ix_webhook_events_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_webhook_events_status ON public.webhook_events USING btree (status);

--
-- Name: uq_financial_years_one_current; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_financial_years_one_current ON public.financial_years USING btree (tenant_id) WHERE is_current;

--
-- Name: uq_financial_years_one_current_fresh; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_financial_years_one_current_fresh ON public.financial_years USING btree (tenant_id) WHERE is_current;

--
-- Name: uq_journal_entries_tenant_reference_fresh; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_journal_entries_tenant_reference_fresh ON public.journal_entries USING btree (tenant_id, reference_number);

--
-- Name: uq_journal_entries_tenant_source_fresh; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_journal_entries_tenant_source_fresh ON public.journal_entries USING btree (tenant_id, source_type, source_id);

--
-- Name: uq_numbering_series_active_document; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_numbering_series_active_document ON public.numbering_series USING btree (tenant_id, document_type) WHERE is_active;

--
-- Name: uq_products_tenant_barcode; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_products_tenant_barcode ON public.products USING btree (tenant_id, barcode) WHERE ((barcode IS NOT NULL) AND (deleted_at IS NULL));

--
-- Name: audit_logs audit_logs_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_immutable BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.apex_prevent_audit_mutation();

--
-- Name: bill_lines ck_bill_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_bill_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, bill_id ON public.bill_lines FOR EACH ROW EXECUTE FUNCTION public.apex_bill_lines_tenant_matches_parent();

--
-- Name: bill_payment_allocations ck_bill_payment_allocations_tenant_matches_parents; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_bill_payment_allocations_tenant_matches_parents BEFORE INSERT OR UPDATE OF tenant_id, payment_id, bill_id ON public.bill_payment_allocations FOR EACH ROW EXECUTE FUNCTION public.apex_allocation_tenant_matches_parents();

--
-- Name: credit_note_lines ck_credit_note_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_credit_note_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, credit_note_id ON public.credit_note_lines FOR EACH ROW EXECUTE FUNCTION public.apex_credit_note_lines_tenant_matches_parent();

--
-- Name: debit_note_lines ck_debit_note_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_debit_note_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, debit_note_id ON public.debit_note_lines FOR EACH ROW EXECUTE FUNCTION public.apex_debit_note_lines_tenant_matches_parent();

--
-- Name: delivery_challan_lines ck_delivery_challan_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_delivery_challan_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, delivery_challan_id ON public.delivery_challan_lines FOR EACH ROW EXECUTE FUNCTION public.apex_delivery_challan_lines_tenant_matches_parent();

--
-- Name: goods_receipt_lines ck_goods_receipt_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_goods_receipt_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, goods_receipt_id ON public.goods_receipt_lines FOR EACH ROW EXECUTE FUNCTION public.apex_goods_receipt_lines_tenant_matches_parent();

--
-- Name: inventory_adjustment_lines ck_inventory_adjustment_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_inventory_adjustment_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, inventory_adjustment_id ON public.inventory_adjustment_lines FOR EACH ROW EXECUTE FUNCTION public.apex_inventory_adjustment_lines_tenant_matches_parent();

--
-- Name: invoice_lines ck_invoice_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_invoice_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, invoice_id ON public.invoice_lines FOR EACH ROW EXECUTE FUNCTION public.apex_invoice_lines_tenant_matches_parent();

--
-- Name: journal_entries ck_journal_entries_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_journal_entries_immutable BEFORE UPDATE ON public.journal_entries FOR EACH ROW EXECUTE FUNCTION public.apex_guard_journal_entries_update();

--
-- Name: journal_entries ck_journal_entries_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_journal_entries_no_delete BEFORE DELETE ON public.journal_entries FOR EACH ROW EXECUTE FUNCTION public.apex_guard_journal_entries_delete();

--
-- Name: journal_entries ck_journal_entry_balanced; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ck_journal_entry_balanced AFTER INSERT OR UPDATE ON public.journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.apex_validate_journal_balance();

--
-- Name: journal_lines ck_journal_lines_balanced; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ck_journal_lines_balanced AFTER INSERT OR DELETE OR UPDATE ON public.journal_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.apex_validate_journal_balance();

--
-- Name: journal_lines ck_journal_lines_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_journal_lines_immutable BEFORE UPDATE ON public.journal_lines FOR EACH ROW EXECUTE FUNCTION public.apex_guard_journal_lines_update();

--
-- Name: journal_lines ck_journal_lines_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_journal_lines_no_delete BEFORE DELETE ON public.journal_lines FOR EACH ROW EXECUTE FUNCTION public.apex_guard_journal_lines_delete();

--
-- Name: journal_lines ck_journal_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_journal_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, entry_id ON public.journal_lines FOR EACH ROW EXECUTE FUNCTION public.apex_journal_lines_tenant_matches_parent();

--
-- Name: payment_allocations ck_payment_allocations_tenant_matches_parents; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_payment_allocations_tenant_matches_parents BEFORE INSERT OR UPDATE OF tenant_id, payment_id, invoice_id ON public.payment_allocations FOR EACH ROW EXECUTE FUNCTION public.apex_allocation_tenant_matches_parents();

--
-- Name: proforma_invoice_lines ck_proforma_invoice_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_proforma_invoice_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, proforma_invoice_id ON public.proforma_invoice_lines FOR EACH ROW EXECUTE FUNCTION public.apex_proforma_invoice_lines_tenant_matches_parent();

--
-- Name: purchase_order_lines ck_purchase_order_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_purchase_order_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, purchase_order_id ON public.purchase_order_lines FOR EACH ROW EXECUTE FUNCTION public.apex_purchase_order_lines_tenant_matches_parent();

--
-- Name: purchase_return_lines ck_purchase_return_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_purchase_return_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, purchase_return_id ON public.purchase_return_lines FOR EACH ROW EXECUTE FUNCTION public.apex_purchase_return_lines_tenant_matches_parent();

--
-- Name: recurring_invoice_items ck_recurring_invoice_items_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_recurring_invoice_items_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, recurring_invoice_id ON public.recurring_invoice_items FOR EACH ROW EXECUTE FUNCTION public.apex_recurring_invoice_items_tenant_matches_parent();

--
-- Name: sales_order_lines ck_sales_order_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_sales_order_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, sales_order_id ON public.sales_order_lines FOR EACH ROW EXECUTE FUNCTION public.apex_sales_order_lines_tenant_matches_parent();

--
-- Name: sales_return_lines ck_sales_return_lines_tenant_matches_parent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_sales_return_lines_tenant_matches_parent BEFORE INSERT OR UPDATE OF tenant_id, sales_return_id ON public.sales_return_lines FOR EACH ROW EXECUTE FUNCTION public.apex_sales_return_lines_tenant_matches_parent();

--
-- Name: stock_ledger ck_stock_ledger_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_stock_ledger_immutable BEFORE UPDATE ON public.stock_ledger FOR EACH ROW EXECUTE FUNCTION public.apex_guard_stock_ledger_update();

--
-- Name: stock_ledger ck_stock_ledger_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ck_stock_ledger_no_delete BEFORE DELETE ON public.stock_ledger FOR EACH ROW EXECUTE FUNCTION public.apex_guard_stock_ledger_delete();

--
-- Name: accounts accounts_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.accounts(id);

--
-- Name: accounts accounts_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: bank_reconciliations bank_reconciliations_bank_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_reconciliations
    ADD CONSTRAINT bank_reconciliations_bank_transaction_id_fkey FOREIGN KEY (bank_transaction_id) REFERENCES public.bank_transactions(id);

--
-- Name: bank_reconciliations bank_reconciliations_bill_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_reconciliations
    ADD CONSTRAINT bank_reconciliations_bill_payment_id_fkey FOREIGN KEY (bill_payment_id) REFERENCES public.bill_payments(id);

--
-- Name: bank_reconciliations bank_reconciliations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_reconciliations
    ADD CONSTRAINT bank_reconciliations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id);

--
-- Name: bank_statements bank_statements_banking_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_statements
    ADD CONSTRAINT bank_statements_banking_profile_id_fkey FOREIGN KEY (banking_profile_id) REFERENCES public.banking_profiles(id);

--
-- Name: bank_transactions bank_transactions_bank_statement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_transactions
    ADD CONSTRAINT bank_transactions_bank_statement_id_fkey FOREIGN KEY (bank_statement_id) REFERENCES public.bank_statements(id);

--
-- Name: banking_profiles banking_profiles_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banking_profiles
    ADD CONSTRAINT banking_profiles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: bill_lines bill_lines_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_lines
    ADD CONSTRAINT bill_lines_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id);

--
-- Name: bill_lines bill_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_lines
    ADD CONSTRAINT bill_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: bill_payment_allocations bill_payment_allocations_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payment_allocations
    ADD CONSTRAINT bill_payment_allocations_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id);

--
-- Name: bill_payment_allocations bill_payment_allocations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payment_allocations
    ADD CONSTRAINT bill_payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.bill_payments(id);

--
-- Name: bill_payments bill_payments_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_payments
    ADD CONSTRAINT bill_payments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: bills bills_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: branches branches_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: credit_note_lines credit_note_lines_credit_note_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_lines
    ADD CONSTRAINT credit_note_lines_credit_note_id_fkey FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id);

--
-- Name: credit_note_lines credit_note_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_lines
    ADD CONSTRAINT credit_note_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: credit_notes credit_notes_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: debit_note_lines debit_note_lines_debit_note_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.debit_note_lines
    ADD CONSTRAINT debit_note_lines_debit_note_id_fkey FOREIGN KEY (debit_note_id) REFERENCES public.debit_notes(id);

--
-- Name: debit_note_lines debit_note_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.debit_note_lines
    ADD CONSTRAINT debit_note_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: debit_notes debit_notes_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.debit_notes
    ADD CONSTRAINT debit_notes_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: delivery_challan_lines delivery_challan_lines_delivery_challan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challan_lines
    ADD CONSTRAINT delivery_challan_lines_delivery_challan_id_fkey FOREIGN KEY (delivery_challan_id) REFERENCES public.delivery_challans(id);

--
-- Name: delivery_challan_lines delivery_challan_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challan_lines
    ADD CONSTRAINT delivery_challan_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: delivery_challans delivery_challans_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challans
    ADD CONSTRAINT delivery_challans_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: delivery_challans delivery_challans_converted_to_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challans
    ADD CONSTRAINT delivery_challans_converted_to_invoice_id_fkey FOREIGN KEY (converted_to_invoice_id) REFERENCES public.invoices(id);

--
-- Name: delivery_challans delivery_challans_source_sales_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_challans
    ADD CONSTRAINT delivery_challans_source_sales_order_id_fkey FOREIGN KEY (source_sales_order_id) REFERENCES public.sales_orders(id);

--
-- Name: eway_bills eway_bills_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eway_bills
    ADD CONSTRAINT eway_bills_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id);

--
-- Name: eway_bills eway_bills_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eway_bills
    ADD CONSTRAINT eway_bills_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: expense_categories expense_categories_linked_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_linked_account_id_fkey FOREIGN KEY (linked_account_id) REFERENCES public.accounts(id);

--
-- Name: expense_categories expense_categories_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: expenses expenses_bank_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES public.accounts(id);

--
-- Name: expenses expenses_expense_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_expense_category_id_fkey FOREIGN KEY (expense_category_id) REFERENCES public.expense_categories(id);

--
-- Name: stock_ledger fk_stock_ledger_reversal_movement; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT fk_stock_ledger_reversal_movement FOREIGN KEY (reversal_movement_id) REFERENCES public.stock_ledger(id);

--
-- Name: stock_ledger fk_stock_ledger_reverses_movement; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT fk_stock_ledger_reverses_movement FOREIGN KEY (reverses_movement_id) REFERENCES public.stock_ledger(id);

--
-- Name: goods_receipt_lines goods_receipt_lines_goods_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT goods_receipt_lines_goods_receipt_id_fkey FOREIGN KEY (goods_receipt_id) REFERENCES public.goods_receipts(id);

--
-- Name: goods_receipt_lines goods_receipt_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT goods_receipt_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: goods_receipt_lines goods_receipt_lines_purchase_order_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT goods_receipt_lines_purchase_order_line_id_fkey FOREIGN KEY (purchase_order_line_id) REFERENCES public.purchase_order_lines(id);

--
-- Name: goods_receipt_lines goods_receipt_lines_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipt_lines
    ADD CONSTRAINT goods_receipt_lines_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.branches(id);

--
-- Name: goods_receipts goods_receipts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT goods_receipts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: goods_receipts goods_receipts_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_receipts
    ADD CONSTRAINT goods_receipts_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id);

--
-- Name: integration_connections integration_connections_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_connections
    ADD CONSTRAINT integration_connections_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: integration_inventory_movement integration_inventory_movement_order_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_inventory_movement
    ADD CONSTRAINT integration_inventory_movement_order_state_id_fkey FOREIGN KEY (order_state_id) REFERENCES public.integration_order_state(id);

--
-- Name: integration_inventory_movement integration_inventory_movement_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_inventory_movement
    ADD CONSTRAINT integration_inventory_movement_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.integration_synced_product_variants(id);

--
-- Name: integration_invoice_line_map integration_invoice_line_map_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_invoice_line_map
    ADD CONSTRAINT integration_invoice_line_map_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: integration_invoice_line_map integration_invoice_line_map_invoice_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_invoice_line_map
    ADD CONSTRAINT integration_invoice_line_map_invoice_line_id_fkey FOREIGN KEY (invoice_line_id) REFERENCES public.invoice_lines(id);

--
-- Name: integration_order_state integration_order_state_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_state
    ADD CONSTRAINT integration_order_state_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: integration_order_state integration_order_state_sales_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_order_state
    ADD CONSTRAINT integration_order_state_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES public.sales_orders(id);

--
-- Name: integration_payment_inventory_movement integration_payment_inventory_movement_order_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_inventory_movement
    ADD CONSTRAINT integration_payment_inventory_movement_order_state_id_fkey FOREIGN KEY (order_state_id) REFERENCES public.integration_order_state(id);

--
-- Name: integration_payment_inventory_movement integration_payment_inventory_movement_payment_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_inventory_movement
    ADD CONSTRAINT integration_payment_inventory_movement_payment_state_id_fkey FOREIGN KEY (payment_state_id) REFERENCES public.integration_payment_state(id);

--
-- Name: integration_payment_inventory_movement integration_payment_inventory_movement_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_inventory_movement
    ADD CONSTRAINT integration_payment_inventory_movement_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.integration_synced_product_variants(id);

--
-- Name: integration_payment_state integration_payment_state_order_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT integration_payment_state_order_state_id_fkey FOREIGN KEY (order_state_id) REFERENCES public.integration_order_state(id);

--
-- Name: integration_payment_state integration_payment_state_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_payment_state
    ADD CONSTRAINT integration_payment_state_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id);

--
-- Name: integration_synced_inventory_levels integration_synced_inventory_levels_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_inventory_levels
    ADD CONSTRAINT integration_synced_inventory_levels_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.integration_synced_products(id);

--
-- Name: integration_synced_inventory_levels integration_synced_inventory_levels_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_inventory_levels
    ADD CONSTRAINT integration_synced_inventory_levels_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.integration_synced_product_variants(id);

--
-- Name: integration_synced_prices integration_synced_prices_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_prices
    ADD CONSTRAINT integration_synced_prices_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.integration_synced_products(id);

--
-- Name: integration_synced_prices integration_synced_prices_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_prices
    ADD CONSTRAINT integration_synced_prices_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.integration_synced_product_variants(id);

--
-- Name: integration_synced_product_variants integration_synced_product_variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_synced_product_variants
    ADD CONSTRAINT integration_synced_product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.integration_synced_products(id);

--
-- Name: inventory_adjustment_lines inventory_adjustment_lines_inventory_adjustment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_lines
    ADD CONSTRAINT inventory_adjustment_lines_inventory_adjustment_id_fkey FOREIGN KEY (inventory_adjustment_id) REFERENCES public.inventory_adjustments(id);

--
-- Name: inventory_adjustment_lines inventory_adjustment_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_lines
    ADD CONSTRAINT inventory_adjustment_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: inventory_carry_forwards inventory_carry_forwards_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_carry_forwards
    ADD CONSTRAINT inventory_carry_forwards_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: invoice_lines invoice_lines_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_lines
    ADD CONSTRAINT invoice_lines_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: invoice_lines invoice_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_lines
    ADD CONSTRAINT invoice_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: invoices invoices_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: journal_entries journal_entries_original_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_original_transaction_id_fkey FOREIGN KEY (original_transaction_id) REFERENCES public.journal_entries(id);

--
-- Name: journal_entries journal_entries_replacement_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_replacement_transaction_id_fkey FOREIGN KEY (replacement_transaction_id) REFERENCES public.journal_entries(id);

--
-- Name: journal_entries journal_entries_reversal_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_reversal_transaction_id_fkey FOREIGN KEY (reversal_transaction_id) REFERENCES public.journal_entries(id);

--
-- Name: journal_entries journal_entries_reverses_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_reverses_transaction_id_fkey FOREIGN KEY (reverses_transaction_id) REFERENCES public.journal_entries(id);

--
-- Name: journal_lines journal_lines_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;

--
-- Name: journal_lines journal_lines_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_entry_id_fkey FOREIGN KEY (entry_id) REFERENCES public.journal_entries(id);

--
-- Name: numbering_series numbering_series_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.numbering_series
    ADD CONSTRAINT numbering_series_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: offline_number_allocations offline_number_allocations_numbering_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_number_allocations
    ADD CONSTRAINT offline_number_allocations_numbering_series_id_fkey FOREIGN KEY (numbering_series_id) REFERENCES public.numbering_series(id);

--
-- Name: offline_number_allocations offline_number_allocations_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_number_allocations
    ADD CONSTRAINT offline_number_allocations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: opening_balance_snapshots opening_balance_snapshots_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opening_balance_snapshots
    ADD CONSTRAINT opening_balance_snapshots_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id);

--
-- Name: password_reset_tokens password_reset_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

--
-- Name: payment_allocations payment_allocations_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: payment_allocations payment_allocations_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocations
    ADD CONSTRAINT payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id);

--
-- Name: payment_terms payment_terms_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_terms
    ADD CONSTRAINT payment_terms_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: payments payments_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: proforma_invoice_lines proforma_invoice_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoice_lines
    ADD CONSTRAINT proforma_invoice_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: proforma_invoice_lines proforma_invoice_lines_proforma_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoice_lines
    ADD CONSTRAINT proforma_invoice_lines_proforma_invoice_id_fkey FOREIGN KEY (proforma_invoice_id) REFERENCES public.proforma_invoices(id);

--
-- Name: proforma_invoices proforma_invoices_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoices
    ADD CONSTRAINT proforma_invoices_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: proforma_invoices proforma_invoices_converted_to_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proforma_invoices
    ADD CONSTRAINT proforma_invoices_converted_to_invoice_id_fkey FOREIGN KEY (converted_to_invoice_id) REFERENCES public.invoices(id);

--
-- Name: purchase_order_lines purchase_order_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT purchase_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: purchase_order_lines purchase_order_lines_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_lines
    ADD CONSTRAINT purchase_order_lines_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id);

--
-- Name: purchase_orders purchase_orders_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: purchase_return_lines purchase_return_lines_bill_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_return_lines
    ADD CONSTRAINT purchase_return_lines_bill_line_id_fkey FOREIGN KEY (bill_line_id) REFERENCES public.bill_lines(id);

--
-- Name: purchase_return_lines purchase_return_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_return_lines
    ADD CONSTRAINT purchase_return_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: purchase_return_lines purchase_return_lines_purchase_return_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_return_lines
    ADD CONSTRAINT purchase_return_lines_purchase_return_id_fkey FOREIGN KEY (purchase_return_id) REFERENCES public.purchase_returns(id);

--
-- Name: purchase_returns purchase_returns_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_returns
    ADD CONSTRAINT purchase_returns_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id);

--
-- Name: purchase_returns purchase_returns_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_returns
    ADD CONSTRAINT purchase_returns_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: recurring_invoice_items recurring_invoice_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_invoice_items
    ADD CONSTRAINT recurring_invoice_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: recurring_invoice_items recurring_invoice_items_recurring_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_invoice_items
    ADD CONSTRAINT recurring_invoice_items_recurring_invoice_id_fkey FOREIGN KEY (recurring_invoice_id) REFERENCES public.recurring_invoices(id);

--
-- Name: recurring_invoices recurring_invoices_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_invoices
    ADD CONSTRAINT recurring_invoices_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: recurring_invoices recurring_invoices_source_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_invoices
    ADD CONSTRAINT recurring_invoices_source_invoice_id_fkey FOREIGN KEY (source_invoice_id) REFERENCES public.invoices(id);

--
-- Name: sales_order_lines sales_order_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT sales_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: sales_order_lines sales_order_lines_sales_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_order_lines
    ADD CONSTRAINT sales_order_lines_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES public.sales_orders(id);

--
-- Name: sales_orders sales_orders_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: sales_orders sales_orders_converted_to_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_converted_to_invoice_id_fkey FOREIGN KEY (converted_to_invoice_id) REFERENCES public.invoices(id);

--
-- Name: sales_orders sales_orders_source_proforma_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_orders
    ADD CONSTRAINT sales_orders_source_proforma_id_fkey FOREIGN KEY (source_proforma_id) REFERENCES public.proforma_invoices(id);

--
-- Name: sales_return_lines sales_return_lines_invoice_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_return_lines
    ADD CONSTRAINT sales_return_lines_invoice_line_id_fkey FOREIGN KEY (invoice_line_id) REFERENCES public.invoice_lines(id);

--
-- Name: sales_return_lines sales_return_lines_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_return_lines
    ADD CONSTRAINT sales_return_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: sales_return_lines sales_return_lines_sales_return_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_return_lines
    ADD CONSTRAINT sales_return_lines_sales_return_id_fkey FOREIGN KEY (sales_return_id) REFERENCES public.sales_returns(id);

--
-- Name: sales_returns sales_returns_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_returns
    ADD CONSTRAINT sales_returns_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);

--
-- Name: sales_returns sales_returns_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_returns
    ADD CONSTRAINT sales_returns_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);

--
-- Name: stock_ledger stock_ledger_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

--
-- Name: stock_ledger stock_ledger_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.branches(id);

--
-- Name: tax_templates tax_templates_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_templates
    ADD CONSTRAINT tax_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: tenant_invitations tenant_invitations_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_invitations
    ADD CONSTRAINT tenant_invitations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: tenant_memberships tenant_memberships_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: tenant_memberships tenant_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

--
-- Name: tenant_settings tenant_settings_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_settings
    ADD CONSTRAINT tenant_settings_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: terms_templates terms_templates_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms_templates
    ADD CONSTRAINT terms_templates_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);

--
-- Name: accounting_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounting_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: bank_reconciliations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bank_reconciliations ENABLE ROW LEVEL SECURITY;

--
-- Name: bank_statements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bank_statements ENABLE ROW LEVEL SECURITY;

--
-- Name: banking_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banking_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: bill_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bill_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: bill_payment_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bill_payment_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: bill_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bill_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: bills; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;

--
-- Name: branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: credit_note_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_note_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: credit_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: debit_note_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.debit_note_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: debit_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.debit_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: delivery_challan_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_challan_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: delivery_challans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_challans ENABLE ROW LEVEL SECURITY;

--
-- Name: eway_bills; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.eway_bills ENABLE ROW LEVEL SECURITY;

--
-- Name: expense_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- Name: financial_year_audits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.financial_year_audits ENABLE ROW LEVEL SECURITY;

--
-- Name: financial_years; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.financial_years ENABLE ROW LEVEL SECURITY;

--
-- Name: goods_receipt_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goods_receipt_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: goods_receipts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goods_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: gst_returns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gst_returns ENABLE ROW LEVEL SECURITY;

--
-- Name: idempotency_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_connections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_connections ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_dead_letter; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_dead_letter ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_entity_map; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_entity_map ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_event_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_event_log ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_inventory_movement; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_inventory_movement ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_invoice_line_map; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_invoice_line_map ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_master_sync_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_master_sync_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_order_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_order_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_order_state; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_order_state ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_payment_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_payment_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_payment_inventory_movement; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_payment_inventory_movement ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_payment_state; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_payment_state ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_replay_cache; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_replay_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_synced_customers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_synced_customers ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_synced_inventory_levels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_synced_inventory_levels ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_synced_prices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_synced_prices ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_synced_product_variants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_synced_product_variants ENABLE ROW LEVEL SECURITY;

--
-- Name: integration_synced_products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.integration_synced_products ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_adjustment_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_adjustment_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_carry_forwards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_carry_forwards ENABLE ROW LEVEL SECURITY;

--
-- Name: invoice_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoice_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: journal_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: journal_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: numbering_series; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.numbering_series ENABLE ROW LEVEL SECURITY;

--
-- Name: offline_number_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.offline_number_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: opening_balance_snapshots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opening_balance_snapshots ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_allocations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_terms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_terms ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: period_lock_audits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.period_lock_audits ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: proforma_invoice_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proforma_invoice_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: proforma_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.proforma_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_return_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_return_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_returns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_returns ENABLE ROW LEVEL SECURITY;

--
-- Name: recurring_invoice_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recurring_invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: recurring_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recurring_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_return_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_return_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: sales_returns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sales_returns ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_ledger; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_ledger ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sync_events ENABLE ROW LEVEL SECURITY;

--
-- Name: tax_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: accounting_periods tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.accounting_periods USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: accounts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.accounts USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: audit_logs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_logs USING (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)))) WITH CHECK (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))));

--
-- Name: bank_reconciliations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bank_reconciliations USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: bank_statements tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bank_statements USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: banking_profiles tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.banking_profiles USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: bill_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bill_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: bill_payment_allocations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bill_payment_allocations USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: bill_payments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bill_payments USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: bills tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bills USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: branches tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.branches USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: contacts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.contacts USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: credit_note_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.credit_note_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: credit_notes tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.credit_notes USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: debit_note_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.debit_note_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: debit_notes tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.debit_notes USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: delivery_challan_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.delivery_challan_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: delivery_challans tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.delivery_challans USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: eway_bills tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.eway_bills USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: expense_categories tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.expense_categories USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: expenses tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.expenses USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: financial_year_audits tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.financial_year_audits USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: financial_years tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.financial_years USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: goods_receipt_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.goods_receipt_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: goods_receipts tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.goods_receipts USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: gst_returns tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.gst_returns USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: idempotency_keys tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.idempotency_keys USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_connections tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_connections USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_dead_letter tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_dead_letter USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_entity_map tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_entity_map USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_event_log tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_event_log USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_inventory_movement tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_inventory_movement USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_invoice_line_map tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_invoice_line_map USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_master_sync_audit tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_master_sync_audit USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_order_audit tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_order_audit USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_order_state tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_order_state USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_payment_audit tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_payment_audit USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_payment_inventory_movement tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_payment_inventory_movement USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_payment_state tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_payment_state USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_replay_cache tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_replay_cache USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_synced_customers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_synced_customers USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_synced_inventory_levels tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_synced_inventory_levels USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_synced_prices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_synced_prices USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_synced_product_variants tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_synced_product_variants USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: integration_synced_products tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.integration_synced_products USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: inventory_adjustment_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.inventory_adjustment_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: inventory_adjustments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.inventory_adjustments USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: inventory_carry_forwards tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.inventory_carry_forwards USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: invoice_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invoice_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: invoices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.invoices USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: journal_entries tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.journal_entries USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: journal_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.journal_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: numbering_series tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.numbering_series USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: offline_number_allocations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.offline_number_allocations USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: opening_balance_snapshots tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.opening_balance_snapshots USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: payment_allocations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payment_allocations USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: payment_terms tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payment_terms USING (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)))) WITH CHECK (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))));

--
-- Name: payments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.payments USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: period_lock_audits tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.period_lock_audits USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: products tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.products USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: proforma_invoice_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.proforma_invoice_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: proforma_invoices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.proforma_invoices USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: purchase_order_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.purchase_order_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: purchase_orders tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.purchase_orders USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: purchase_return_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.purchase_return_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: purchase_returns tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.purchase_returns USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: recurring_invoice_items tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.recurring_invoice_items USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: recurring_invoices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.recurring_invoices USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: sales_order_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sales_order_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: sales_orders tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sales_orders USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: sales_return_lines tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sales_return_lines USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: sales_returns tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sales_returns USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: stock_ledger tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.stock_ledger USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: sync_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sync_events USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: tax_templates tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tax_templates USING (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)))) WITH CHECK (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))));

--
-- Name: tenant_invitations tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tenant_invitations USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: tenant_settings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tenant_settings USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: terms_templates tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.terms_templates USING (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)))) WITH CHECK (((tenant_id IS NULL) OR ((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))));

--
-- Name: transfers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.transfers USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: webhook_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.webhook_events USING (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true))) WITH CHECK (((tenant_id)::text = current_setting('app.current_tenant_id'::text, true)));

--
-- Name: tenant_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: terms_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.terms_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: transfers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.transfers ENABLE ROW LEVEL SECURITY;

--
-- Name: webhook_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

--
--

"""


def _schema_exists(bind) -> bool:
    inspector = sa.inspect(bind)
    return "tenants" in inspector.get_table_names()


def upgrade() -> None:
    """Create the complete schema on an empty database; no-op on existing."""
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        # SQLite test databases are built by the test fixtures, not here.
        return

    # New-chain revision ids exceed the 32-character default of the
    # alembic_version.version_num column.  Widen it first so the later
    # revisions can be recorded.  On an existing deployment this requires
    # the ownership transfer (scripts/transfer_ownership.py) to have run.
    try:
        bind.execute(
            sa.text(
                "ALTER TABLE alembic_version "
                "ALTER COLUMN version_num TYPE VARCHAR(255)"
            )
        )
    except Exception as exc:  # pragma: no cover - environment dependent
        raise RuntimeError(
            "Cannot widen alembic_version for the squashed baseline. "
            "Run scripts/transfer_ownership.py first so the migration role "
            "owns the schema. (%s)" % exc
        ) from exc

    if _schema_exists(bind):
        # Existing deployment (stamped through the legacy chain): the schema
        # is already exactly this snapshot.  Record the revision and let the
        # delta migrations (20260811_0001 .. 0004) continue.
        return

    bind.execute(sa.text(_BASELINE_SQL))


def downgrade() -> None:
    """Not supported: a squashed baseline has no reversible downgrade path.

    Existing deployments never run this revision (they are stamped over it),
    so a downgrade target would be meaningless.  Fresh databases that need to
    roll back should restore a backup instead.
    """
    raise NotImplementedError(
        "20260811_0000_squashed_baseline cannot be downgraded; restore from backup."
    )
