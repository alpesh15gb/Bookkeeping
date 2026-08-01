import 'package:apexbooks/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prunes only old terminal sync history', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.utc(2026, 7, 31, 12);
    final old = now.subtract(const Duration(days: 31));
    final recent = now.subtract(const Duration(days: 2));

    Future<void> insertOperation({
      required String id,
      required String status,
      DateTime? completedAt,
    }) {
      return db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: id,
              entityType: 'journal',
              entityLocalId: 'entity-$id',
              companyId: const Value('company-1'),
              actorId: const Value('actor-1'),
              deviceId: const Value('device-1'),
              operationType: 'create',
              payload: '{}',
              idempotencyKey: 'key-$id',
              status: status,
              createdAt: old,
              completedAt: Value(completedAt),
            ),
          );
    }

    await insertOperation(id: 'old-synced', status: 'synced', completedAt: old);
    await insertOperation(
      id: 'recent-synced',
      status: 'synced',
      completedAt: recent,
    );
    await insertOperation(id: 'old-failed', status: 'failed', completedAt: old);
    await insertOperation(id: 'old-pending', status: 'pending');

    Future<void> insertConflict({
      required String id,
      String? resolution,
      DateTime? resolvedAt,
    }) {
      return db
          .into(db.syncConflicts)
          .insert(
            SyncConflictsCompanion.insert(
              id: id,
              entityType: 'invoice',
              entityLocalId: 'entity-$id',
              localPayload: '{}',
              remotePayload: '{}',
              detectedAt: old,
              resolution: Value(resolution),
              resolvedAt: Value(resolvedAt),
            ),
          );
    }

    await insertConflict(
      id: 'old-resolved',
      resolution: 'kept_remote',
      resolvedAt: old,
    );
    await insertConflict(
      id: 'recent-resolved',
      resolution: 'kept_local',
      resolvedAt: recent,
    );
    await insertConflict(id: 'old-unresolved');

    expect(await db.pruneSyncHistory(now: now), 2);

    final remainingOperations = await db.select(db.syncOperations).get();
    expect(
      remainingOperations.map((row) => row.id),
      containsAll(<String>['recent-synced', 'old-failed', 'old-pending']),
    );
    expect(
      remainingOperations.map((row) => row.id),
      isNot(contains('old-synced')),
    );

    final remainingConflicts = await db.select(db.syncConflicts).get();
    expect(
      remainingConflicts.map((row) => row.id),
      containsAll(<String>['recent-resolved', 'old-unresolved']),
    );
    expect(
      remainingConflicts.map((row) => row.id),
      isNot(contains('old-resolved')),
    );
  });
}
