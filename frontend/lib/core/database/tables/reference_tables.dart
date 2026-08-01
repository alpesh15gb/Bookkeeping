/// Drift table definitions for reference data pulled from the server.
///
/// These tables are populated by [SyncEngine.runPullCycle] from the
/// `/apexbooks/sync/pull` event stream.  The UI reads them reactively
/// through Drift streams.
///
/// Both tables carry sync metadata so the pull engine can track state
/// without a separate join.  Records are identified by `(companyId, remoteId)`
/// for idempotent replay of pull events.
library;

import 'package:drift/drift.dart';

class CompanyProfiles extends Table {
  TextColumn get companyId => text()();
  TextColumn get originStateCode => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {companyId};
}

// ── Chart of accounts ─────────────────────────────────────────────────────────

/// One row per account pulled from the server (account.created/updated events).
class Accounts extends Table {
  /// Stable client UUID (generated locally or assigned from the first pull).
  TextColumn get localId => text()();

  /// Server UUID — used for idempotent pull-event application.
  TextColumn get remoteId => text()();

  /// FK — every reference record belongs to exactly one company.
  TextColumn get companyId => text()();

  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get accountType => text()();

  /// Parent account ID (remoteId), or null for top-level accounts.
  TextColumn get parentRemoteId => text().nullable()();

  TextColumn get accountGroup => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Opening balance in paise (100 paise = ₹1).
  IntColumn get openingBalancePaise =>
      integer().withDefault(const Constant(0))();

  // Sync metadata — tracks when this record was last pulled.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};

  /// Unique on (companyId, remoteId) ensures idempotent pull-event replay.
  List<Set<Column>> get uniqueConstraints => [
    {companyId, remoteId},
  ];
}

// ── Contacts (parties) ────────────────────────────────────────────────────────

/// One row per contact (customer, vendor, or both) pulled from the server.
class Contacts extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text()();
  TextColumn get companyId => text()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();

  /// One of: `'customer'`, `'vendor'`, `'both'`.
  TextColumn get contactType => text()();
  TextColumn get gstin => text().nullable()();
  TextColumn get stateCode => text().nullable()();

  /// Tenant-scoped control accounts provisioned by the server. Financial
  /// transactions must use these IDs instead of a contact UUID.
  TextColumn get receivableAccountId => text().nullable()();
  TextColumn get payableAccountId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Opening balance in paise.
  IntColumn get openingBalancePaise =>
      integer().withDefault(const Constant(0))();

  // Sync metadata.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};

  /// Unique on (companyId, remoteId) ensures idempotent pull-event replay.
  List<Set<Column>> get uniqueConstraints => [
    {companyId, remoteId},
  ];
}
