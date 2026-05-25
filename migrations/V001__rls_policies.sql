-- ============================================================================
-- PostgreSQL Row-Level Security (RLS) Migration
-- Run this against your PostgreSQL database after all tables are created.
-- Target: bookkeeping (or bookkeeping_test)
-- ============================================================================

-- 1. Enable RLS on every tenant-scoped table
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE banking_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_note_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE debit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE debit_note_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE bill_payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE proforma_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE proforma_invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_challans ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_challan_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_adjustment_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_reconciliations ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE gst_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE numbering_series ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_invitations ENABLE ROW LEVEL SECURITY;

-- 2. Helper function to get the current tenant_id from session setting
-- (set by set_rls_tenant_context event listener in src/core/database.py)
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid
LANGUAGE SQL
STABLE
AS $$
  SELECT NULLIF(current_setting('app.current_tenant_id', TRUE), '')::uuid;
$$;

-- 3. Drop existing policies before creating (idempotent for re-runs)
DO $$ DECLARE
  tbl text;
  pol text;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'tenants', 'users', 'tenant_memberships', 'contacts', 'products',
      'accounts', 'banking_profiles', 'expense_categories',
      'invoices', 'invoice_lines', 'credit_notes', 'credit_note_lines',
      'debit_notes', 'debit_note_lines',
      'bills', 'bill_lines', 'bill_payments', 'bill_payment_allocations',
      'payments', 'payment_allocations',
      'journal_entries', 'journal_lines',
      'proforma_invoices', 'proforma_invoice_lines',
      'delivery_challans', 'delivery_challan_lines',
      'sales_orders', 'sales_order_lines',
      'purchase_orders', 'purchase_order_lines',
      'inventory_adjustments', 'inventory_adjustment_lines',
      'bank_statements', 'bank_transactions', 'bank_reconciliations',
      'stock_ledger', 'audit_logs', 'gst_returns', 'webhook_events',
      'tenant_settings', 'numbering_series', 'branches', 'tenant_invitations'
    ])
  LOOP
    FOR pol IN
      SELECT policyname FROM pg_policies WHERE tablename = tbl AND schemaname = 'public'
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol, tbl);
    END LOOP;
  END LOOP;
END $$;

-- 4. Create tenant-scoped SELECT policy for each table
--    (only rows belonging to the session's tenant_id are visible)

CREATE POLICY tenant_isolation_select ON tenants
  FOR SELECT USING (id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON users
  FOR SELECT USING (id IN (
    SELECT user_id FROM tenant_memberships WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON tenant_memberships
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON contacts
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON products
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON accounts
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON banking_profiles
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON expense_categories
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON invoices
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON invoice_lines
  FOR SELECT USING (invoice_id IN (
    SELECT id FROM invoices WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON credit_notes
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON credit_note_lines
  FOR SELECT USING (credit_note_id IN (
    SELECT id FROM credit_notes WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON debit_notes
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON debit_note_lines
  FOR SELECT USING (debit_note_id IN (
    SELECT id FROM debit_notes WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON bills
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON bill_lines
  FOR SELECT USING (bill_id IN (
    SELECT id FROM bills WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON bill_payments
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON bill_payment_allocations
  FOR SELECT USING (payment_id IN (
    SELECT id FROM bill_payments WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON payments
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON payment_allocations
  FOR SELECT USING (payment_id IN (
    SELECT id FROM payments WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON journal_entries
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON journal_lines
  FOR SELECT USING (entry_id IN (
    SELECT id FROM journal_entries WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON proforma_invoices
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON proforma_invoice_lines
  FOR SELECT USING (proforma_invoice_id IN (
    SELECT id FROM proforma_invoices WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON delivery_challans
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON delivery_challan_lines
  FOR SELECT USING (delivery_challan_id IN (
    SELECT id FROM delivery_challans WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON sales_orders
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON sales_order_lines
  FOR SELECT USING (sales_order_id IN (
    SELECT id FROM sales_orders WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON purchase_orders
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON purchase_order_lines
  FOR SELECT USING (purchase_order_id IN (
    SELECT id FROM purchase_orders WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON inventory_adjustments
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON inventory_adjustment_lines
  FOR SELECT USING (inventory_adjustment_id IN (
    SELECT id FROM inventory_adjustments WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON bank_statements
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON bank_transactions
  FOR SELECT USING (bank_statement_id IN (
    SELECT id FROM bank_statements WHERE tenant_id = current_tenant_id()
  ));

CREATE POLICY tenant_isolation_select ON bank_reconciliations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM bank_transactions bt
      JOIN bank_statements bs ON bs.id = bt.bank_statement_id
      WHERE bt.id = bank_reconciliations.bank_transaction_id
      AND bs.tenant_id = current_tenant_id()
    )
  );

CREATE POLICY tenant_isolation_select ON stock_ledger
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON audit_logs
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON gst_returns
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON webhook_events
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON tenant_settings
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON numbering_series
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON branches
  FOR SELECT USING (tenant_id = current_tenant_id());

CREATE POLICY tenant_isolation_select ON tenant_invitations
  FOR SELECT USING (tenant_id = current_tenant_id());

-- 5. Create INSERT/UPDATE/DELETE policies (same tenant-scoped rules)
--    Note: These apply BYPASSRLS to application users. The application
--    should connect with a role that has BYPASSRLS set, OR create
--    corresponding policies for each DML operation.

-- For a production setup where the app connects as an unprivileged role,
-- uncomment and adapt the following pattern for each table:
--
-- CREATE POLICY tenant_isolation_insert ON invoices
--   FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
--
-- CREATE POLICY tenant_isolation_update ON invoices
--   FOR UPDATE USING (tenant_id = current_tenant_id());
--
-- CREATE POLICY tenant_isolation_delete ON invoices
--   FOR DELETE USING (tenant_id = current_tenant_id());
