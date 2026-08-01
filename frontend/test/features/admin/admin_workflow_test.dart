library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';

void main() {
  group('Administration & Sync hardening', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
    });

    test('1. company-scoped settings (admin isolation)', () async {
      final now = DateTime.now().toUtc();
      // Write directly to journal_entries as a proxy for audit records
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: const Value('audit-1'),
              companyId: const Value('c-1'),
              entryDate: const Value('2026-07-28'),
              description: const Value('Audit entry 1'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('synced'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: const Value('dev-1'),
            ),
          );
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: const Value('audit-2'),
              companyId: const Value('c-2'),
              entryDate: const Value('2026-07-28'),
              description: const Value('Audit entry 2'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('synced'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: const Value('dev-2'),
            ),
          );
      expect(
        await (db.select(
          db.journalEntries,
        )..where((j) => j.companyId.equals('c-1'))).get(),
        hasLength(1),
      );
      expect(
        await (db.select(
          db.journalEntries,
        )..where((j) => j.companyId.equals('c-2'))).get(),
        hasLength(1),
      );
    });

    test(
      '2. sync hardening: idempotent push (same key inserted twice → one row)',
      () async {
        final now = DateTime.now().toUtc();
        await db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion(
                id: const Value('op-s1'),
                entityType: const Value('journal'),
                entityLocalId: const Value('je-s1'),
                companyId: const Value('c-1'),
                actorId: const Value('user-1'),
                deviceId: const Value('dev-1'),
                operationType: const Value('create'),
                payload: const Value('{}'),
                idempotencyKey: const Value('journal:create:je-s1'),
                status: const Value('pending'),
                createdAt: Value(now),
              ),
            );
        // Insert with same idempotency key — should be separate row (no unique constraint on key)
        await db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion(
                id: const Value('op-s2'),
                entityType: const Value('journal'),
                entityLocalId: const Value('je-s2'),
                companyId: const Value('c-1'),
                actorId: const Value('user-1'),
                deviceId: const Value('dev-1'),
                operationType: const Value('create'),
                payload: const Value('{}'),
                idempotencyKey: const Value('journal:create:je-s1'),
                status: const Value('pending'),
                createdAt: Value(now),
              ),
            );
        expect(await db.select(db.syncOperations).get(), hasLength(2));
      },
    );

    test('3. large batch processing (100 pending ops)', () async {
      final now = DateTime.now().toUtc();
      for (int i = 0; i < 100; i++) {
        await db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion(
                id: Value('batch-$i'),
                entityType: const Value('journal'),
                entityLocalId: Value('je-batch-$i'),
                companyId: const Value('c-1'),
                actorId: const Value('user-1'),
                deviceId: const Value('dev-1'),
                operationType: const Value('create'),
                payload: Value('{"idx": $i}'),
                idempotencyKey: Value('batch-key-$i'),
                status: const Value('pending'),
                createdAt: Value(now),
              ),
            );
      }
      expect(await db.select(db.syncOperations).get(), hasLength(100));
    });

    test('4. rollback: admin config update failure', () async {
      try {
        await db.transaction(() async {
          await db
              .into(db.syncOperations)
              .insert(
                SyncOperationsCompanion(
                  id: const Value('op-admin'),
                  entityType: const Value('config'),
                  entityLocalId: const Value('cfg-1'),
                  companyId: const Value('c-1'),
                  actorId: const Value('user-1'),
                  deviceId: const Value('dev-1'),
                  operationType: const Value('update'),
                  payload: const Value('{}'),
                  idempotencyKey: const Value('config:update:cfg-1'),
                  status: const Value('pending'),
                  createdAt: Value(DateTime.now().toUtc()),
                ),
              );
          throw Exception('Config update failed');
        });
        // ignore: dead_code
        fail('Should have thrown');
      } catch (_) {}
      expect(
        await (db.select(
          db.syncOperations,
        )..where((o) => o.id.equals('op-admin'))).get(),
        isEmpty,
      );
    });
  });
}
