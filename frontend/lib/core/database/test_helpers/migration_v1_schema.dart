/// V1 schema replica for migration testing.
library;

import 'package:drift/drift.dart';

part 'migration_v1_schema.g.dart';

class JournalEntriesV1 extends Table {
  @override
  String get tableName => 'journal_entries';

  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get entryDate => text()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text()();
  TextColumn get sourceType => text().withDefault(const Constant('MANUAL'))();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();
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

class JournalLinesV1 extends Table {
  @override
  String get tableName => 'journal_lines';

  TextColumn get localId => text()();
  TextColumn get journalLocalId => text()();
  TextColumn get accountId => text()();
  TextColumn get accountCode => text()();
  TextColumn get accountName => text()();
  TextColumn get direction => text()();
  IntColumn get amountPaise => integer()();
  TextColumn get narration => text().nullable()();
  IntColumn get sortOrder => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}

class SyncOperationsV1 extends Table {
  @override
  String get tableName => 'sync_operations';

  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityLocalId => text()();
  TextColumn get operationType => text()();
  TextColumn get payload => text()();
  TextColumn get idempotencyKey => text()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get dependencyIds => text().nullable()();
  TextColumn get status => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncConflictsV1 extends Table {
  @override
  String get tableName => 'sync_conflicts';

  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityLocalId => text()();
  TextColumn get localPayload => text()();
  TextColumn get remotePayload => text()();
  DateTimeColumn get detectedAt => dateTime()();
  TextColumn get resolution => text().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncCheckpointsV1 extends Table {
  @override
  String get tableName => 'sync_checkpoints';

  TextColumn get companyId => text()();
  TextColumn get entityType => text()();
  IntColumn get lastServerSequence =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {companyId, entityType};
}

/// Drift database at schema v1 — used ONLY for migration test fixtures.
@DriftDatabase(
  tables: [
    JournalEntriesV1,
    JournalLinesV1,
    SyncOperationsV1,
    SyncConflictsV1,
    SyncCheckpointsV1,
  ],
)
class V1Database extends _$V1Database {
  V1Database(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL;');
      await customStatement('PRAGMA foreign_keys=ON;');
    },
  );
}
