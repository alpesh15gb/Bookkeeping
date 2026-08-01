/// Drift table definitions for the purchasing workflow.
library;

import 'package:drift/drift.dart';

// ── Purchase orders ──────────────────────────────────────────────────────────

class PurchaseOrders extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get orderDate => text()();
  TextColumn get supplierId => text()();
  TextColumn get supplierName => text()();

  /// 'DRAFT', 'CONFIRMED', 'RECEIVED', 'CANCELLED'
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();

  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();

  /// Total amount in paise (authoritative — computed by repository).
  IntColumn get totalPaise => integer()();

  /// How much of the order has been received (quantity sum).
  TextColumn get receivedQuantity => text().withDefault(const Constant('0'))();
  TextColumn get currency => text().withDefault(const Constant('INR'))();

  // Sync metadata
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
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

class PurchaseOrderLines extends Table {
  TextColumn get localId => text()();
  TextColumn get purchaseOrderLocalId => text()();
  TextColumn get productName => text()();
  TextColumn get description => text().nullable()();
  TextColumn get unit => text()();
  IntColumn get unitPricePaise => integer()();
  TextColumn get quantityOrdered => text()(); // precision text
  TextColumn get quantityReceived => text().withDefault(const Constant('0'))();
  IntColumn get totalPaise => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}

// ── Purchase receipts (goods receipt notes) ──────────────────────────────────

class PurchaseReceipts extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get purchaseOrderLocalId => text()();
  TextColumn get receiptDate => text()();
  TextColumn get supplierId => text()();
  TextColumn get supplierName => text()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();

  /// 'POSTED' after successful transactional receipt.
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('draft'))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
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

class PurchaseReceiptLines extends Table {
  TextColumn get localId => text()();
  TextColumn get receiptLocalId => text()();
  TextColumn get purchaseOrderLineLocalId => text()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  TextColumn get quantityReceived => text()();
  IntColumn get unitCostPaise => integer()();
  IntColumn get totalPaise => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}

// ── Purchase invoices (supplier bills) ───────────────────────────────────────

class PurchaseInvoices extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get invoiceNumber => text()();
  TextColumn get invoiceDate => text()();
  TextColumn get supplierId => text()();
  TextColumn get supplierName => text()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();

  IntColumn get totalBeforeTaxPaise => integer()();
  IntColumn get taxPaise => integer()();
  IntColumn get totalPaise => integer()();

  /// 'DRAFT', 'POSTED'
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('DRAFT'))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
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

class PurchaseInvoiceLines extends Table {
  TextColumn get localId => text()();
  TextColumn get invoiceLocalId => text()();
  TextColumn get productName => text()();
  TextColumn get description => text().nullable()();
  TextColumn get unit => text()();
  IntColumn get unitPricePaise => integer()();
  TextColumn get quantity => text()();
  IntColumn get totalPaise => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}
