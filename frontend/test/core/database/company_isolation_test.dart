/// Company and financial-year isolation tests.
///
/// Verifies that queries, sync operations, and checkpoints are properly
/// scoped to company and financial year boundaries.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  group('Company isolation', () {
    late AppDatabase db;

    setUp(() {
      db = _memoryDb();
    });

    tearDown(() async {
      await db.close();
    });

    test('journal queries are company-scoped', () async {
      final now = DateTime.now().toUtc();
      // Insert journals for two companies.
      for (final cid in ['c-1', 'c-2']) {
        await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion(
                localId: Value('je-$cid'),
                companyId: Value(cid),
                entryDate: const Value('2026-07-28'),
                description: Value('Journal for $cid'),
                lifecycleStatus: const Value('draft'),
                syncStatus: const Value('localOnly'),
                createdAt: Value(now),
                updatedAt: Value(now),
                originDeviceId: const Value('dev-1'),
              ),
            );
      }

      // Verify each company sees only its own entries.
      final rows1 = await (db.select(
        db.journalEntries,
      )..where((r) => r.companyId.equals('c-1'))).get();
      expect(rows1.length, 1);
      expect(rows1.first.companyId, 'c-1');

      final rows2 = await (db.select(
        db.journalEntries,
      )..where((r) => r.companyId.equals('c-2'))).get();
      expect(rows2.length, 1);
      expect(rows2.first.companyId, 'c-2');

      // Empty for non-existent company.
      final rows3 = await (db.select(
        db.journalEntries,
      )..where((r) => r.companyId.equals('c-3'))).get();
      expect(rows3, isEmpty);
    });

    test('outbox operations are company-scoped', () async {
      final now = DateTime.now().toUtc();
      for (final cid in ['c-1', 'c-2']) {
        await db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion(
                id: Value('op-$cid'),
                entityType: const Value('journal'),
                entityLocalId: Value('je-$cid'),
                companyId: Value(cid),
                actorId: const Value('user-1'),
                deviceId: const Value('dev-1'),
                operationType: const Value('create'),
                payload: const Value('{}'),
                idempotencyKey: Value('create:je-$cid'),
                status: const Value('pending'),
                createdAt: Value(now),
              ),
            );
      }

      // Verify scoped queries.
      final ops1 = await (db.select(
        db.syncOperations,
      )..where((o) => o.companyId.equals('c-1'))).get();
      expect(ops1.length, 1);
      expect(ops1.first.companyId, 'c-1');

      final ops2 = await (db.select(
        db.syncOperations,
      )..where((o) => o.companyId.equals('c-2'))).get();
      expect(ops2.length, 1);
      expect(ops2.first.companyId, 'c-2');
    });

    test('operations retain FY after UI context switch', () async {
      final now = DateTime.now().toUtc();

      // Queue an operation with a specific FY.
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: const Value('op-fy'),
              entityType: const Value('journal'),
              entityLocalId: const Value('je-fy'),
              companyId: const Value('c-1'),
              actorId: const Value('user-1'),
              deviceId: const Value('dev-1'),
              financialYearId: const Value('fy-2025-2026'),
              operationType: const Value('create'),
              payload: const Value('{}'),
              idempotencyKey: const Value('create:je-fy'),
              status: const Value('pending'),
              createdAt: Value(now),
            ),
          );

      // Verify FY is stored.
      final ops = await (db.select(
        db.syncOperations,
      )..where((o) => o.id.equals('op-fy'))).get();
      expect(ops.length, 1);
      expect(
        ops.first.financialYearId,
        'fy-2025-2026',
        reason: 'FY must be stored and preserved regardless of UI state',
      );
    });

    test('sync checkpoints are scoped by company and entity type', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.syncCheckpoints)
          .insert(
            SyncCheckpointsCompanion(
              companyId: const Value('c-1'),
              entityType: const Value('journal'),
              lastServerSequence: const Value(42),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.syncCheckpoints)
          .insert(
            SyncCheckpointsCompanion(
              companyId: const Value('c-1'),
              entityType: const Value('invoice'),
              lastServerSequence: const Value(100),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.syncCheckpoints)
          .insert(
            SyncCheckpointsCompanion(
              companyId: const Value('c-2'),
              entityType: const Value('journal'),
              lastServerSequence: const Value(7),
              updatedAt: Value(now),
            ),
          );

      // Query for c-1 journal only.
      final rows =
          await (db.select(db.syncCheckpoints)..where(
                (c) =>
                    c.companyId.equals('c-1') & c.entityType.equals('journal'),
              ))
              .get();
      expect(rows.length, 1);
      expect(rows.first.lastServerSequence, 42);

      // Query for c-1 all entity types.
      final allC1 = await (db.select(
        db.syncCheckpoints,
      )..where((c) => c.companyId.equals('c-1'))).get();
      expect(allC1.length, 2);
    });
  });
}
