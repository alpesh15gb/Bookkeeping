/// Drift tables for customer returns (credit notes) and supplier returns (debit notes).
library;

import 'package:drift/drift.dart';

class SalesReturns extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get returnDate => text()();
  TextColumn get customerId => text()();
  TextColumn get customerName => text()();
  TextColumn get sourceInvoiceLocalId => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get totalPaise => integer()();
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

class SalesReturnLines extends Table {
  TextColumn get localId => text()();
  TextColumn get returnLocalId => text()();
  TextColumn get sourceInvoiceLineLocalId => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  TextColumn get quantity => text()();
  IntColumn get unitPricePaise => integer()();
  IntColumn get totalPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}

class PurchaseReturns extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get returnDate => text()();
  TextColumn get supplierId => text()();
  TextColumn get supplierName => text()();
  TextColumn get sourceReceiptLocalId => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get totalPaise => integer()();
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

class PurchaseReturnLines extends Table {
  TextColumn get localId => text()();
  TextColumn get returnLocalId => text()();
  TextColumn get sourceReceiptLineLocalId => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  TextColumn get quantity => text()();
  IntColumn get unitCostPaise => integer()();
  IntColumn get totalPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}
