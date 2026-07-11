/// Client-side role → permission map mirroring the backend `ROLE_PERMISSIONS`
/// in `src/core/security.py`. The API does not expose the current user's
/// permissions, so the frontend maintains this map to show/hide UI elements.
/// The backend enforces permissions on every request regardless.
library;

import '../../features/auth/data/models/membership_models.dart';

/// All permission codes used by the ApexBooks backend.
class Permissions {
  Permissions._();

  static const tenantView = 'tenant:view';
  static const tenantUpdate = 'tenant:update';
  static const settingsView = 'settings:view';
  static const settingsUpdate = 'settings:update';
  static const contactCreate = 'contact:create';
  static const contactView = 'contact:view';
  static const contactUpdate = 'contact:update';
  static const contactDelete = 'contact:delete';
  static const invoiceCreate = 'invoice:create';
  static const invoiceView = 'invoice:view';
  static const invoiceUpdate = 'invoice:update';
  static const invoiceFinalize = 'invoice:finalize';
  static const invoiceDelete = 'invoice:delete';
  static const paymentCreate = 'payment:create';
  static const paymentView = 'payment:view';
  static const paymentDelete = 'payment:delete';
  static const paymentCancel = 'payment:cancel';
  static const ledgerView = 'ledger:view';
  static const ledgerManualPost = 'ledger:manual_post';
  static const accountsManage = 'accounts:manage';
  static const gstReportView = 'gst:report_view';
  static const gstFilingManage = 'gst:filing_manage';
  static const creditNoteCreate = 'credit_note:create';
  static const creditNoteView = 'credit_note:view';
  static const debitNoteCreate = 'debit_note:create';
  static const debitNoteView = 'debit_note:view';
  static const auditView = 'audit:view';
  static const reportsView = 'reports:view';
  static const expenseCreate = 'expense:create';
  static const expenseView = 'expense:view';
  static const expenseEdit = 'expense:edit';
  static const expenseDelete = 'expense:delete';
  static const expenseFinalize = 'expense:finalize';
  static const billCreate = 'bill:create';
  static const billView = 'bill:view';
  static const billUpdate = 'bill:update';
  static const billDelete = 'bill:delete';
}

/// Role → permission list, matching the backend matrix.
const Map<MemberRole, Set<String>> rolePermissions = {
  MemberRole.owner: {
    Permissions.tenantView,
    Permissions.tenantUpdate,
    Permissions.settingsView,
    Permissions.settingsUpdate,
    Permissions.contactCreate,
    Permissions.contactView,
    Permissions.contactUpdate,
    Permissions.contactDelete,
    Permissions.invoiceCreate,
    Permissions.invoiceView,
    Permissions.invoiceUpdate,
    Permissions.invoiceFinalize,
    Permissions.invoiceDelete,
    Permissions.paymentCreate,
    Permissions.paymentView,
    Permissions.paymentDelete,
    Permissions.paymentCancel,
    Permissions.ledgerView,
    Permissions.ledgerManualPost,
    Permissions.accountsManage,
    Permissions.gstReportView,
    Permissions.gstFilingManage,
    Permissions.creditNoteCreate,
    Permissions.creditNoteView,
    Permissions.debitNoteCreate,
    Permissions.debitNoteView,
    Permissions.auditView,
    Permissions.reportsView,
    Permissions.expenseCreate,
    Permissions.expenseView,
    Permissions.expenseEdit,
    Permissions.expenseDelete,
    Permissions.expenseFinalize,
    Permissions.billCreate,
    Permissions.billView,
    Permissions.billUpdate,
    Permissions.billDelete,
  },
  MemberRole.accountant: {
    Permissions.tenantView,
    Permissions.settingsView,
    Permissions.settingsUpdate,
    Permissions.contactCreate,
    Permissions.contactView,
    Permissions.contactUpdate,
    Permissions.invoiceView,
    Permissions.invoiceFinalize,
    Permissions.paymentCreate,
    Permissions.paymentView,
    Permissions.paymentCancel,
    Permissions.ledgerView,
    Permissions.ledgerManualPost,
    Permissions.accountsManage,
    Permissions.gstReportView,
    Permissions.gstFilingManage,
    Permissions.creditNoteCreate,
    Permissions.creditNoteView,
    Permissions.debitNoteCreate,
    Permissions.debitNoteView,
    Permissions.auditView,
    Permissions.reportsView,
    Permissions.expenseCreate,
    Permissions.expenseView,
    Permissions.expenseEdit,
    Permissions.expenseFinalize,
    Permissions.billCreate,
    Permissions.billView,
    Permissions.billUpdate,
    Permissions.billDelete,
  },
  MemberRole.salesperson: {
    Permissions.contactCreate,
    Permissions.contactView,
    Permissions.contactUpdate,
    Permissions.invoiceCreate,
    Permissions.invoiceView,
    Permissions.invoiceUpdate,
    Permissions.paymentCreate,
  },
  MemberRole.auditor: {
    Permissions.tenantView,
    Permissions.invoiceView,
    Permissions.contactView,
    Permissions.paymentView,
    Permissions.ledgerView,
    Permissions.reportsView,
    Permissions.auditView,
    Permissions.billView,
    Permissions.expenseView,
    Permissions.creditNoteView,
    Permissions.debitNoteView,
    Permissions.gstReportView,
    Permissions.settingsView,
  },
};

/// Returns the set of permissions granted to [role].
Set<String> permissionsFor(MemberRole role) =>
    rolePermissions[role] ?? const <String>{};

/// `true` when [role] grants [permission].
bool hasPermission(MemberRole role, String permission) =>
    permissionsFor(role).contains(permission);
