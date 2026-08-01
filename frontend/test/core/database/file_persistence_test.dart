/// File-backed persistence test.
///
/// Verifies that journal entries, lines, outbox operations, and retry state
/// survive a close/reopen cycle on a real SQLite file.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/sync/sync_status.dart';

void main() {
  group('File-backed persistence', () {
    late File dbFile;

    setUp(() {
      dbFile = File(
        '${Directory.systemTemp.path}/apex_persist_${DateTime.now().millisecondsSinceEpoch}.db',
      );
    });

    tearDown(() async {
      if (dbFile.existsSync()) await dbFile.delete();
    });

    test('journal + outbox survive close/reopen', () async {
      // ── Open, write, close ───────────────────────────────────────────
      final db1 = AppDatabase(NativeDatabase(dbFile));
      final now = DateTime.now().toUtc();
      final retryAt = now.add(const Duration(minutes: 5));

      await db1.transaction(() async {
        // Journal header
        await db1
            .into(db1.journalEntries)
            .insert(
              JournalEntriesCompanion(
                localId: const Value('je-persist'),
                companyId: const Value('c-1'),
                entryDate: const Value('2026-07-28'),
                referenceNumber: const Value('JNL-0001'),
                description: const Value('Persistence test'),
                lifecycleStatus: const Value('posted'),
                sourceType: const Value('MANUAL'),
                syncStatus: Value(SyncStatus.pending.name),
                localRevision: const Value(3),
                remoteRevision: const Value(2),
                isDirty: const Value(true),
                createdAt: Value(now),
                updatedAt: Value(now),
                originDeviceId: const Value('dev-1'),
              ),
            );

        // Journal lines
        await db1
            .into(db1.journalLines)
            .insert(
              const JournalLinesCompanion(
                localId: Value('jl-persist-1'),
                journalLocalId: Value('je-persist'),
                accountId: Value('acc-cash'),
                accountCode: Value('1001'),
                accountName: Value('Cash'),
                direction: Value('DEBIT'),
                amountPaise: Value(50000),
                narration: Value('Test debit'),
                sortOrder: Value(0),
              ),
            );
        await db1
            .into(db1.journalLines)
            .insert(
              const JournalLinesCompanion(
                localId: Value('jl-persist-2'),
                journalLocalId: Value('je-persist'),
                accountId: Value('acc-rev'),
                accountCode: Value('4001'),
                accountName: Value('Revenue'),
                direction: Value('CREDIT'),
                amountPaise: Value(50000),
                sortOrder: Value(1),
              ),
            );

        // Outbox operation with scheduled retry
        await db1
            .into(db1.syncOperations)
            .insert(
              SyncOperationsCompanion(
                id: const Value('op-persist'),
                entityType: const Value('journal'),
                entityLocalId: const Value('je-persist'),
                companyId: const Value('c-1'),
                actorId: const Value('user-1'),
                deviceId: const Value('dev-1'),
                financialYearId: const Value('fy-2026'),
                operationType: const Value('create'),
                payload: const Value('{"test": true}'),
                idempotencyKey: const Value('journal:create:je-persist'),
                priority: const Value(0),
                attemptCount: const Value(2),
                nextAttemptAt: Value(retryAt),
                status: const Value('pending'),
                createdAt: Value(now),
                lastError: const Value('Previous failure'),
              ),
            );
      });

      await db1.close();

      // ── Reopen, verify ─────────────────────────────────────────────
      final db2 = AppDatabase(NativeDatabase(dbFile));

      // Journal header
      final journals = await db2.select(db2.journalEntries).get();
      expect(journals.length, 1);
      final j = journals.first;
      expect(j.localId, 'je-persist');
      expect(j.companyId, 'c-1');
      expect(j.entryDate, '2026-07-28');
      expect(j.referenceNumber, 'JNL-0001');
      expect(j.description, 'Persistence test');
      expect(j.lifecycleStatus, 'posted');
      expect(j.sourceType, 'MANUAL');
      expect(j.syncStatus, SyncStatus.pending.name);
      expect(j.localRevision, 3);
      expect(j.remoteRevision, 2);
      expect(j.isDirty, true);
      expect(j.originDeviceId, 'dev-1');

      // Journal lines
      final lines =
          await (db2.select(db2.journalLines)
                ..where((l) => l.journalLocalId.equals('je-persist'))
                ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
              .get();
      expect(lines.length, 2);
      expect(lines[0].accountName, 'Cash');
      expect(lines[0].amountPaise, 50000);
      expect(lines[0].direction, 'DEBIT');
      expect(lines[1].accountName, 'Revenue');
      expect(lines[1].amountPaise, 50000);
      expect(lines[1].direction, 'CREDIT');

      // Outbox operation with retry scheduling
      final ops = await db2.select(db2.syncOperations).get();
      expect(ops.length, 1);
      final op = ops.first;
      expect(op.id, 'op-persist');
      expect(op.entityType, 'journal');
      expect(op.entityLocalId, 'je-persist');
      expect(op.companyId, 'c-1');
      expect(op.financialYearId, 'fy-2026');
      expect(op.actorId, 'user-1');
      expect(op.deviceId, 'dev-1');
      expect(op.operationType, 'create');
      expect(op.idempotencyKey, 'journal:create:je-persist');
      expect(op.attemptCount, 2);
      expect(op.status, 'pending');
      expect(op.lastError, 'Previous failure');

      // Retry scheduling survived: nextAttemptAt should be ~5 min after creation
      expect(op.nextAttemptAt, isNotNull);
      expect(
        op.nextAttemptAt!.difference(now).inSeconds,
        closeTo(300, 10),
      ); // 5 min ±10s

      await db2.close();
    });
  });
}
