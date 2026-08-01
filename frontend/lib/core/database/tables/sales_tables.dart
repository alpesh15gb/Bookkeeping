/// Drift table definitions for sales fulfillment.
library;

import 'package:drift/drift.dart';

// ── Sales orders ──────────────────────────────────────────────────────────────

class SalesOrders extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get orderDate => text()();
  TextColumn get customerId => text()();
  TextColumn get customerName => text()();

  /// 'DRAFT', 'CONFIRMED', 'DELIVERING', 'DELIVERED', 'INVOICED', 'CANCELLED'
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get totalPaise => integer()();
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

class SalesOrderLines extends Table {
  TextColumn get localId => text()();
  TextColumn get salesOrderLocalId => text()();
  TextColumn get productName => text()();
  TextColumn get description => text().nullable()();
  TextColumn get unit => text()();
  IntColumn get unitPricePaise => integer()();
  TextColumn get quantityOrdered => text()();
  TextColumn get quantityDelivered => text().withDefault(const Constant('0'))();
  TextColumn get quantityInvoiced => text().withDefault(const Constant('0'))();
  IntColumn get totalPaise => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}

// ── Sales deliveries (dispatch / delivery challans) ───────────────────────────

class SalesDeliveries extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get salesOrderLocalId => text()();
  TextColumn get deliveryDate => text()();
  TextColumn get customerId => text()();
  TextColumn get customerName => text()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();

  /// 'posted'
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

class SalesDeliveryLines extends Table {
  TextColumn get localId => text()();
  TextColumn get deliveryLocalId => text()();
  TextColumn get salesOrderLineLocalId => text()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  TextColumn get quantityDelivered => text()();
  IntColumn get unitPricePaise => integer()();
  IntColumn get totalPaise => integer()();
  IntColumn get sortOrder => integer()();

  /// How much of this delivery line has been invoiced.
  TextColumn get quantityInvoiced => text().withDefault(const Constant('0'))();

  @override
  Set<Column> get primaryKey => {localId};
}
