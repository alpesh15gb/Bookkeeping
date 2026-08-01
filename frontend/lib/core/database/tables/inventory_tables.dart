/// Drift table definitions for inventory management.
library;

import 'package:drift/drift.dart';

// ── Stock items (product master extended for inventory) ───────────────────────

class StockItems extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get name => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get unit => text()(); // 'PCS', 'KGS', 'NOS', 'HRS', etc.
  TextColumn get hsnSac => text().nullable()();
  IntColumn get salesPricePaise => integer().withDefault(const Constant(0))();
  IntColumn get gstRateBasisPoints =>
      integer().withDefault(const Constant(0))();

  /// Current stock quantity (text for arbitrary precision).
  TextColumn get currentQuantity => text().withDefault(const Constant('0'))();

  /// Moving average or last purchase cost in paise.
  IntColumn get unitCostPaise => integer().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  // Sync metadata
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

// ── Inventory movements (transaction ledger) ─────────────────────────────────

class InventoryMovements extends Table {
  TextColumn get localId => text()();
  TextColumn get companyId => text()();
  TextColumn get stockItemId => text()();

  /// 'RECEIPT', 'ISSUE', 'TRANSFER_IN', 'TRANSFER_OUT', 'ADJUSTMENT'
  TextColumn get movementType => text()();

  /// Quantity change (positive for in, negative for out).
  TextColumn get quantity => text()(); // signed text for precision

  /// Running balance after this movement (always non-negative for physical stock).
  TextColumn get balanceAfter => text()();

  /// Unit cost at time of movement in paise.
  IntColumn get unitCostPaise => integer()();

  /// Total value of the movement in paise.
  IntColumn get totalPaise => integer()();

  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get movementDate => text()(); // ISO date

  // Sync metadata — movements sync as events
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

// ── Inventory balances (denormalized for fast reads) ──────────────────────────

class InventoryBalances extends Table {
  TextColumn get localId => text()();
  TextColumn get companyId => text()();
  TextColumn get stockItemId => text()();

  /// Warehouse or location ID.
  TextColumn get locationId => text().withDefault(const Constant('default'))();

  /// Current quantity on hand.
  TextColumn get quantityOnHand => text().withDefault(const Constant('0'))();

  /// Moving average cost in paise.
  IntColumn get averageCostPaise => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};

  List<Set<Column>> get uniqueConstraints => [
    {companyId, stockItemId, locationId},
  ];
}
