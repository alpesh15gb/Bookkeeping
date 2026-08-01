/// Drift table definitions for payments (receipts and payments).
library;

import 'package:drift/drift.dart';

// ── Payments ──────────────────────────────────────────────────────────────────

/// One row per payment (receipt from customer or payment to vendor).
///
/// Payments are immutable after posting.  The posted payment creates a journal
/// entry and may be allocated against one or more invoices.
class Payments extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();

  // ── Business fields ─────────────────────────────────────────────────────────

  /// 'RECEIPT' (money in) or 'PAYMENT' (money out).
  TextColumn get paymentType => text()();

  /// ISO date of the payment.
  TextColumn get paymentDate => text()();

  TextColumn get referenceNumber => text().nullable()();

  /// Contact (customer or vendor).
  TextColumn get contactId => text()();
  TextColumn get contactName => text()();

  /// Payment method: 'CASH', 'BANK', 'UPI', 'CHEQUE', 'CARD', etc.
  TextColumn get paymentMode => text()();

  /// Bank account / cash account remote ID.
  TextColumn get accountId => text()();

  /// Total amount in paise.
  IntColumn get amountPaise => integer()();

  /// Optional narration.
  TextColumn get description => text().nullable()();

  // ── Lifecycle & sync ────────────────────────────────────────────────────────

  /// 'draft' or 'posted'.
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('draft'))();

  /// SyncStatus.name.
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();

  IntColumn get localRevision => integer().withDefault(const Constant(0))();
  IntColumn get remoteRevision => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get syncError => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  TextColumn get originDeviceId => text()();

  @override
  Set<Column> get primaryKey => {localId};
}

// ── Payment allocations ───────────────────────────────────────────────────────

/// Links a posted payment to one or more invoices.
class PaymentAllocations extends Table {
  TextColumn get localId => text()();
  TextColumn get paymentLocalId => text()();
  TextColumn get invoiceLocalId => text()();
  TextColumn get invoiceRemoteId => text().nullable()();

  /// Amount allocated to this invoice in paise.
  IntColumn get allocatedPaise => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}
