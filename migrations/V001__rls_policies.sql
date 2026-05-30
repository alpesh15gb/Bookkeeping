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
--    These policies enforce tenant isolation for all DML operations.
--    The application connects with a role that has BYPASSRLS set for simplicity,
--    but these policies provide defense-in-depth if RLS is enforced.

-- INSERT policies: tenant_id must match the session's tenant
CREATE POLICY tenant_isolation_insert ON invoices FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON invoice_lines FOR INSERT WITH CHECK (invoice_id IN (SELECT id FROM invoices WHERE tenant_id = current_tenant_id()));
CREATE POLICY tenant_isolation_insert ON contacts FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON products FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON accounts FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON payments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON payment_allocations FOR INSERT WITH CHECK (payment_id IN (SELECT id FROM payments WHERE tenant_id = current_tenant_id()));
CREATE POLICY tenant_isolation_insert ON bills FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON bill_lines FOR INSERT WITH CHECK (bill_id IN (SELECT id FROM bills WHERE tenant_id = current_tenant_id()));
CREATE POLICY tenant_isolation_insert ON bill_payments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON bill_payment_allocations FOR INSERT WITH CHECK (payment_id IN (SELECT id FROM bill_payments WHERE tenant_id = current_tenant_id()));
CREATE POLICY tenant_isolation_insert ON journal_entries FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON journal_lines FOR INSERT WITH CHECK (entry_id IN (SELECT id FROM journal_entries WHERE tenant_id = current_tenant_id()));
CREATE POLICY tenant_isolation_insert ON credit_notes FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON debit_notes FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON expenses FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON expense_categories FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON banking_profiles FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON stock_ledger FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON audit_logs FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON proforma_invoices FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON delivery_challans FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON sales_orders FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON purchase_orders FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON inventory_adjustments FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON gst_returns FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON bank_statements FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON bank_reconciliations FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON numbering_series FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON branches FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON tenant_settings FOR INSERT WITH CHECK (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_insert ON webhook_events FOR INSERT WITH CHECK (tenant_id = current_tenant_id());

-- UPDATE policies: can only update rows belonging to the session's tenant
CREATE POLICY tenant_isolation_update ON invoices FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON contacts FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON products FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON accounts FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON payments FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON bills FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON bill_payments FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON journal_entries FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON credit_notes FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON debit_notes FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON expenses FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON banking_profiles FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON stock_ledger FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON proforma_invoices FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON delivery_challans FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON sales_orders FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON purchase_orders FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON inventory_adjustments FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON bank_statements FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON bank_reconciliations FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON numbering_series FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON branches FOR UPDATE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_update ON tenant_settings FOR UPDATE USING (tenant_id = current_tenant_id());

-- DELETE policies: can only delete rows belonging to the session's tenant
CREATE POLICY tenant_isolation_delete ON invoices FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON contacts FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON products FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON accounts FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON payments FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON bills FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON bill_payments FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON journal_entries FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON credit_notes FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON debit_notes FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON expenses FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON banking_profiles FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON stock_ledger FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON proforma_invoices FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON delivery_challans FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON sales_orders FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON purchase_orders FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON inventory_adjustments FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON bank_statements FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON bank_reconciliations FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON numbering_series FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON branches FOR DELETE USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation_delete ON tenant_settings FOR DELETE USING (tenant_id = current_tenant_id());
