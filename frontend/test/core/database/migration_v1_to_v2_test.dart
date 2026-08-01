/// Migration test: schema v1 → v2.
///
/// Uses [V1Database] to create a genuine v1 Drift schema.  Opens with
/// [AppDatabase] v2 which triggers [MigrationStrategy.onUpgrade] from 1 → 2.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/database/test_helpers/migration_v1_schema.dart'
    as v1;

import 'dart:io';

void main() {
  group('v1 → v2 migration', () {
    late File dbFile;

    setUp(() {
      dbFile = File(
        '${Directory.systemTemp.path}/apex_v1migrate_${DateTime.now().millisecondsSinceEpoch}.db',
      );
    });

    tearDown(() async {
      if (dbFile.existsSync()) await dbFile.delete();
    });

    /// Helper: open v2, run assertions, close.
    Future<void> withV2(Future<void> Function(AppDatabase) fn) async {
      final db = AppDatabase(NativeDatabase(dbFile));
      try {
        await fn(db);
      } finally {
        await db.close();
      }
    }

    test('existing journals survive upgrade', () async {
      final v1db = v1.V1Database(NativeDatabase(dbFile));
      final now = DateTime.now().toUtc();
      await v1db
          .into(v1db.journalEntriesV1)
          .insert(
            v1.JournalEntriesV1Companion(
              localId: const Value('je-1'),
              companyId: const Value('c-1'),
              entryDate: const Value('2026-07-01'),
              description: const Value('Survival journal'),
              status: const Value('POSTED'),
              syncStatus: const Value('synced'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: const Value('dev-1'),
            ),
          );
      await v1db
          .into(v1db.journalLinesV1)
          .insert(
            const v1.JournalLinesV1Companion(
              localId: Value('jl-1'),
              journalLocalId: Value('je-1'),
              accountId: Value('acc-1'),
              accountCode: Value('1001'),
              accountName: Value('Cash'),
              direction: Value('DEBIT'),
              amountPaise: Value(50000),
              sortOrder: Value(0),
            ),
          );
      await v1db.close();

      await withV2((db) async {
        final journals = await db.select(db.journalEntries).get();
        expect(journals.length, 1);
        expect(journals.first.localId, 'je-1');
        expect(journals.first.description, 'Survival journal');

        final lines = await (db.select(
          db.journalLines,
        )..where((l) => l.journalLocalId.equals('je-1'))).get();
        expect(lines.length, 1);
        expect(lines.first.amountPaise, 50000);
      });
    });

    test('old status values map into lifecycleStatus', () async {
      final v1db = v1.V1Database(NativeDatabase(dbFile));
      final now = DateTime.now().toUtc();
      for (final entry in [('je-draft', 'DRAFT'), ('je-posted', 'POSTED')]) {
        await v1db
            .into(v1db.journalEntriesV1)
            .insert(
              v1.JournalEntriesV1Companion(
                localId: Value(entry.$1),
                companyId: const Value('c-1'),
                entryDate: const Value('2026-07-01'),
                description: Value('${entry.$2} journal'),
                status: Value(entry.$2),
                syncStatus: const Value('localOnly'),
                createdAt: Value(now),
                updatedAt: Value(now),
                originDeviceId: const Value('dev-1'),
              ),
            );
      }
      await v1db.close();

      await withV2((db) async {
        final rows = await db.select(db.journalEntries).get();
        expect(rows.length, 2);
        expect(
          rows.firstWhere((r) => r.localId == 'je-draft').lifecycleStatus,
          'draft',
        );
        expect(
          rows.firstWhere((r) => r.localId == 'je-posted').lifecycleStatus,
          'posted',
        );
      });
    });

    test('outbox payloads and idempotency keys unchanged', () async {
      final v1db = v1.V1Database(NativeDatabase(dbFile));
      final now = DateTime.now().toUtc();
      await v1db
          .into(v1db.syncOperationsV1)
          .insert(
            v1.SyncOperationsV1Companion(
              id: const Value('op-1'),
              entityType: const Value('journal'),
              entityLocalId: const Value('je-1'),
              operationType: const Value('create'),
              payload: const Value('{"original":true}'),
              idempotencyKey: const Value('journal:create:je-1'),
              status: const Value('pending'),
              attemptCount: const Value(2),
              createdAt: Value(now),
              lastError: const Value('Prev err'),
            ),
          );
      await v1db.close();

      await withV2((db) async {
        final ops = await db.select(db.syncOperations).get();
        expect(ops.length, 1);
        expect(ops.first.payload, '{"original":true}');
        expect(ops.first.idempotencyKey, 'journal:create:je-1');
        expect(ops.first.attemptCount, 2);
        expect(ops.first.lastError, 'Prev err');
        expect(ops.first.companyId, isEmpty);
        expect(ops.first.financialYearId == null, isTrue);
      });
    });

    test('reopening migrated database is idempotent', () async {
      final v1db = v1.V1Database(NativeDatabase(dbFile));
      final now = DateTime.now().toUtc();
      await v1db
          .into(v1db.journalEntriesV1)
          .insert(
            v1.JournalEntriesV1Companion(
              localId: const Value('je-idemp'),
              companyId: const Value('c-1'),
              entryDate: const Value('2026-07-01'),
              description: const Value('Idempotent'),
              status: const Value('DRAFT'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: const Value('dev-1'),
            ),
          );
      await v1db.close();

      // First open runs onUpgrade.
      await withV2((db) async {
        expect((await db.select(db.journalEntries).get()).length, 1);
      });
      // Second open must not crash.
      await withV2((db) async {
        final rows = await db.select(db.journalEntries).get();
        expect(rows.length, 1);
        expect(rows.first.lifecycleStatus, 'draft');
      });
    });

    test('all core tables are queryable after migration', () async {
      final v1db = v1.V1Database(NativeDatabase(dbFile));
      await v1db.close();

      await withV2((db) async {
        await expectLater(db.select(db.journalEntries).get(), completes);
        await expectLater(db.select(db.journalLines).get(), completes);
        await expectLater(db.select(db.syncOperations).get(), completes);
        await expectLater(db.select(db.syncConflicts).get(), completes);
        await expectLater(db.select(db.syncCheckpoints).get(), completes);
      });
    });
  });
}
