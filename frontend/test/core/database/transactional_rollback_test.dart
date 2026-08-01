/// Transactional rollback tests.
///
/// Verifies that the journal + outbox write is atomic: if any step in the
/// transaction fails, NO change is committed — not the entity, not the lines,
/// not the outbox operation.  Also verifies that a successful write creates
/// exactly one outbox row.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/sync/sync_status.dart';

/// Helper: opens an in-memory AppDatabase.
AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() {
    db = _memoryDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('Transactional atomicity', () {
    test(
      'successful journal + outbox write creates exactly one outbox row',
      () async {
        final now = DateTime.now().toUtc();
        await db.transaction(() async {
          // Insert journal header
          await db
              .into(db.journalEntries)
              .insert(
                JournalEntriesCompanion(
                  localId: const Value('je-1'),
                  companyId: const Value('c-1'),
                  entryDate: const Value('2026-07-28'),
                  description: const Value('Atomicity test'),
                  lifecycleStatus: const Value('draft'),
                  syncStatus: Value(SyncStatus.pending.name),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                  originDeviceId: const Value('dev-1'),
                ),
              );
          // Insert a journal line
          await db
              .into(db.journalLines)
              .insert(
                const JournalLinesCompanion(
                  localId: Value('jl-1'),
                  journalLocalId: Value('je-1'),
                  accountId: Value('acc-1'),
                  accountCode: Value('1001'),
                  accountName: Value('Cash'),
                  direction: Value('DEBIT'),
                  amountPaise: Value(10000),
                  sortOrder: Value(0),
                ),
              );
          // Insert outbox operation
          await db
              .into(db.syncOperations)
              .insert(
                SyncOperationsCompanion(
                  id: const Value('op-1'),
                  entityType: const Value('journal'),
                  entityLocalId: const Value('je-1'),
                  companyId: const Value('c-1'),
                  actorId: const Value('user-1'),
                  deviceId: const Value('dev-1'),
                  operationType: const Value('create'),
                  payload: const Value('{}'),
                  idempotencyKey: const Value('journal:create:je-1'),
                  status: const Value('pending'),
                  createdAt: Value(now),
                ),
              );
        });

        // Verify exactly one of each.
        final journals = await db.select(db.journalEntries).get();
        expect(journals.length, 1);
        final lines = await db.select(db.journalLines).get();
        expect(lines.length, 1);
        final ops = await db.select(db.syncOperations).get();
        expect(
          ops.length,
          1,
          reason: 'Successful write must create exactly one outbox row',
        );
      },
    );

    test('failure before any insert → nothing committed', () async {
      try {
        await db.transaction(() async {
          // This insert will never execute because we throw first.
          throw Exception('Pre-insert failure');
        });
      } catch (_) {
        // Expected.
      }

      final journals = await db.select(db.journalEntries).get();
      expect(journals, isEmpty, reason: 'No journal should exist');
      final lines = await db.select(db.journalLines).get();
      expect(lines, isEmpty, reason: 'No lines should exist');
      final ops = await db.select(db.syncOperations).get();
      expect(ops, isEmpty, reason: 'No outbox entries should exist');
    });

    test(
      'journal insert succeeds, outbox insert fails → both rolled back',
      () async {
        final now = DateTime.now().toUtc();
        try {
          await db.transaction(() async {
            await db
                .into(db.journalEntries)
                .insert(
                  JournalEntriesCompanion(
                    localId: const Value('je-rollback'),
                    companyId: const Value('c-1'),
                    entryDate: const Value('2026-07-28'),
                    description: const Value('Rollback test'),
                    lifecycleStatus: const Value('draft'),
                    syncStatus: Value(SyncStatus.pending.name),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );

            // Simulate outbox failure (e.g. constraint violation).
            // Insert an incomplete row that violates a NOT NULL constraint.
            await db
                .into(db.syncOperations)
                .insert(
                  SyncOperationsCompanion(
                    id: const Value('op-fail'),
                    // Deliberately omit required field entityType to trigger error.
                    entityLocalId: const Value('je-rollback'),
                    companyId: const Value('c-1'),
                    actorId: const Value('user-1'),
                    deviceId: const Value('dev-1'),
                    operationType: const Value('create'),
                    payload: const Value('{}'),
                    idempotencyKey: const Value('key'),
                    status: const Value('pending'),
                    createdAt: Value(now),
                  ),
                );
          });
          fail('Transaction should have thrown due to missing entityType');
        } catch (_) {
          // Expected — transaction rolled back.
        }

        // Verify nothing was committed.
        final journals = await db.select(db.journalEntries).get();
        expect(
          journals,
          isEmpty,
          reason: 'Journal must be rolled back with the outbox failure',
        );
        final ops = await db.select(db.syncOperations).get();
        expect(
          ops,
          isEmpty,
          reason: 'No outbox entry should remain after rollback',
        );
      },
    );

    test(
      'lines partially insert → no journal, lines, or outbox remains',
      () async {
        final now = DateTime.now().toUtc();
        try {
          await db.transaction(() async {
            await db
                .into(db.journalEntries)
                .insert(
                  JournalEntriesCompanion(
                    localId: const Value('je-lines'),
                    companyId: const Value('c-1'),
                    entryDate: const Value('2026-07-28'),
                    description: const Value('Lines test'),
                    lifecycleStatus: const Value('draft'),
                    syncStatus: Value(SyncStatus.pending.name),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );

            // First line succeeds.
            await db
                .into(db.journalLines)
                .insert(
                  const JournalLinesCompanion(
                    localId: Value('jl-ok'),
                    journalLocalId: Value('je-lines'),
                    accountId: Value('acc-1'),
                    accountCode: Value('1001'),
                    accountName: Value('Cash'),
                    direction: Value('DEBIT'),
                    amountPaise: Value(10000),
                    sortOrder: Value(0),
                  ),
                );

            // Second line fails (missing required fields).
            await db
                .into(db.journalLines)
                .insert(
                  const JournalLinesCompanion(
                    localId: Value('jl-fail'),
                    // journalLocalId omitted
                    accountId: Value('acc-2'),
                    accountCode: Value('4001'),
                    accountName: Value('Revenue'),
                    direction: Value('CREDIT'),
                    amountPaise: Value(10000),
                    sortOrder: Value(1),
                  ),
                );
          });
          fail('Transaction should have thrown due to missing journalLocalId');
        } catch (_) {
          // Expected.
        }

        // Verify nothing committed.
        final journals = await db.select(db.journalEntries).get();
        expect(
          journals,
          isEmpty,
          reason: 'No journal header if lines insert failed',
        );
        final lines = await db.select(db.journalLines).get();
        expect(
          lines,
          isEmpty,
          reason: 'No journal lines if transaction rolled back',
        );
        final ops = await db.select(db.syncOperations).get();
        expect(
          ops,
          isEmpty,
          reason: 'No outbox entry if journal write rolled back',
        );
      },
    );

    test(
      'posting-state update failure → no outbox entry queued for post',
      () async {
        // First, write a journal with its outbox operation (as saveDraft does).
        final now = DateTime.now().toUtc();
        await db.transaction(() async {
          await db
              .into(db.journalEntries)
              .insert(
                JournalEntriesCompanion(
                  localId: const Value('je-post'),
                  companyId: const Value('c-1'),
                  entryDate: const Value('2026-07-28'),
                  description: const Value('Post test'),
                  lifecycleStatus: const Value('draft'),
                  syncStatus: Value(SyncStatus.pending.name),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                  originDeviceId: const Value('dev-1'),
                ),
              );
          await db
              .into(db.syncOperations)
              .insert(
                SyncOperationsCompanion(
                  id: const Value('op-create'),
                  entityType: const Value('journal'),
                  entityLocalId: const Value('je-post'),
                  companyId: const Value('c-1'),
                  actorId: const Value('user-1'),
                  deviceId: const Value('dev-1'),
                  operationType: const Value('create'),
                  payload: const Value('{}'),
                  idempotencyKey: const Value('journal:create:je-post'),
                  status: const Value('pending'),
                  createdAt: Value(now),
                ),
              );
        });

        // Now simulate a posting transaction that fails.
        try {
          await db.transaction(() async {
            // Update status to posted.
            await (db.update(
              db.journalEntries,
            )..where((r) => r.localId.equals('je-post'))).write(
              const JournalEntriesCompanion(lifecycleStatus: Value('posted')),
            );

            // Simulate outbox insertion failure.
            throw Exception('Outbox write failed');
          });
          // ignore: dead_code
          fail('Transaction should have thrown');
        } catch (_) {
          // Expected.
        }

        // The journal should still be in 'draft' status because the transaction
        // was rolled back — the status update was never committed.
        final journals = await db.select(db.journalEntries).get();
        expect(journals.length, 1);
        expect(
          journals.first.lifecycleStatus,
          'draft',
          reason: 'lifecycleStatus must remain draft after rolled-back post',
        );
        final ops = await db.select(db.syncOperations).get();
        expect(
          ops.length,
          1,
          reason: 'The original create op must still exist',
        );
        expect(
          ops.first.id,
          'op-create',
          reason: 'The surviving op should be the create, not a post op',
        );
      },
    );

    test(
      'outbox created but transaction throws afterwards → nothing committed',
      () async {
        final now = DateTime.now().toUtc();
        try {
          await db.transaction(() async {
            await db
                .into(db.journalEntries)
                .insert(
                  JournalEntriesCompanion(
                    localId: const Value('je-late-fail'),
                    companyId: const Value('c-1'),
                    entryDate: const Value('2026-07-28'),
                    description: const Value('Late failure test'),
                    lifecycleStatus: const Value('draft'),
                    syncStatus: Value(SyncStatus.pending.name),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );

            // Insert journal line.
            await db
                .into(db.journalLines)
                .insert(
                  const JournalLinesCompanion(
                    localId: Value('jl-late'),
                    journalLocalId: Value('je-late-fail'),
                    accountId: Value('acc-1'),
                    accountCode: Value('1001'),
                    accountName: Value('Cash'),
                    direction: Value('DEBIT'),
                    amountPaise: Value(10000),
                    sortOrder: Value(0),
                  ),
                );

            // Insert outbox row (appears to succeed).
            await db
                .into(db.syncOperations)
                .insert(
                  SyncOperationsCompanion(
                    id: const Value('op-late'),
                    entityType: const Value('journal'),
                    entityLocalId: const Value('je-late-fail'),
                    companyId: const Value('c-1'),
                    actorId: const Value('user-1'),
                    deviceId: const Value('dev-1'),
                    operationType: const Value('create'),
                    payload: const Value('{}'),
                    idempotencyKey: const Value('journal:create:je-late-fail'),
                    status: const Value('pending'),
                    createdAt: Value(now),
                  ),
                );

            // Throw AFTER all inserts — transaction must roll back everything.
            throw StateError('Post-outbox failure simulation');
          });
          // ignore: dead_code
          fail('Transaction should have thrown');
        } catch (_) {
          // Expected.
        }

        // Verify absolutely nothing survived.
        final journals = await db.select(db.journalEntries).get();
        expect(journals, isEmpty, reason: 'No journal after late failure');
        final lines = await db.select(db.journalLines).get();
        expect(lines, isEmpty, reason: 'No lines after late failure');
        final ops = await db.select(db.syncOperations).get();
        expect(ops, isEmpty, reason: 'No outbox after late failure');
      },
    );
  });
}
