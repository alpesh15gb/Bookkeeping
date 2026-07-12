/// Typed permission constants matching the backend Permissions Matrix.
/// Source of truth: `docs/PERMISSIONS_MATRIX.md` / backend `src/core/security.py`.
///
/// Every permission check uses these constants — never raw strings.
class Permissions {
  Permissions._();

  // ─── Tenant ───
  static const tenantView = 'tenant:view';
  static const tenantUpdate = 'tenant:update';

  // ─── Settings ───
  static const settingsView = 'settings:view';
  static const settingsUpdate = 'settings:update';

  // ─── Contacts ───
  static const contactCreate = 'contact:create';
  static const contactView = 'contact:view';
  static const contactUpdate = 'contact:update';
  static const contactDelete = 'contact:delete';

  // ─── Invoices ───
  static const invoiceCreate = 'invoice:create';
  static const invoiceView = 'invoice:view';
  static const invoiceUpdate = 'invoice:update';
  static const invoiceFinalize = 'invoice:finalize';
  static const invoiceDelete = 'invoice:delete';

  // ─── Payments ───
  static const paymentCreate = 'payment:create';
  static const paymentView = 'payment:view';
  static const paymentDelete = 'payment:delete';
  static const paymentCancel = 'payment:cancel';

  // ─── Ledger ───
  static const ledgerView = 'ledger:view';
  static const ledgerManualPost = 'ledger:manual_post';

  // ─── Accounts ───
  static const accountsManage = 'accounts:manage';

  // ─── GST ───
  static const gstReportView = 'gst:report_view';
  static const gstFilingManage = 'gst:filing_manage';

  // ─── Credit/Debit Notes ───
  static const creditNoteCreate = 'credit_note:create';
  static const creditNoteView = 'credit_note:view';
  static const debitNoteCreate = 'debit_note:create';
  static const debitNoteView = 'debit_note:view';

  // ─── Audit ───
  static const auditView = 'audit:view';

  // ─── Reports ───
  static const reportsView = 'reports:view';

  // ─── Expenses ───
  static const expenseCreate = 'expense:create';
  static const expenseView = 'expense:view';
  static const expenseEdit = 'expense:edit';
  static const expenseDelete = 'expense:delete';
  static const expenseFinalize = 'expense:finalize';

  // ─── Bills ───
  static const billCreate = 'bill:create';
  static const billView = 'bill:view';
  static const billUpdate = 'bill:update';
  static const billDelete = 'bill:delete';
}
