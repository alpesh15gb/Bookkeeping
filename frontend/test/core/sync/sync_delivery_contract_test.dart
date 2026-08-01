import 'dart:convert';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sync push acknowledgement contract', () {
    const event = {'event_id': 'event-1', 'aggregate_id': 'payment-1'};

    test('accepts the production acknowledgements envelope', () {
      final result = parseSyncPushResponse(
        {
          'acknowledgements': [
            {
              'event_id': 'event-1',
              'server_sequence': 42,
              'revision': '43',
              'duplicate': false,
              'error': null,
            },
          ],
        },
        event,
        entityLabel: 'payment',
      );

      expect(result.remoteId, 'payment-1');
      expect(result.remoteRevision, 43);
    });

    test('surfaces a processing error instead of treating it as success', () {
      expect(
        () => parseSyncPushResponse({
          'acknowledgements': [
            {
              'event_id': 'event-1',
              'server_sequence': 42,
              'duplicate': false,
              'error': 'Unknown event type',
            },
          ],
        }, event),
        throwsA(isA<PermanentSyncException>()),
      );
    });
  });

  test(
    'push is company-scoped and updates non-journal entity metadata',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 7, 31);

      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              localId: 'payment-1',
              companyId: 'company-1',
              paymentType: 'RECEIPT',
              paymentDate: '2026-07-31',
              contactId: 'contact-1',
              contactName: 'Customer',
              paymentMode: 'BANK',
              accountId: 'bank-1',
              amountPaise: 10000,
              syncStatus: const Value('pending'),
              createdAt: now,
              updatedAt: now,
              isDirty: const Value(true),
              originDeviceId: 'device-1',
            ),
          );

      Future<void> queue({
        required String id,
        required String entityLocalId,
        required String companyId,
      }) {
        return db
            .into(db.syncOperations)
            .insert(
              SyncOperationsCompanion.insert(
                id: id,
                entityType: 'payment',
                entityLocalId: entityLocalId,
                companyId: Value(companyId),
                actorId: const Value('actor-1'),
                deviceId: const Value('device-1'),
                operationType: 'create',
                payload: jsonEncode({
                  'event_id': id,
                  'aggregate_id': entityLocalId,
                }),
                idempotencyKey: id,
                createdAt: now,
                status: SyncStatus.pending.name,
              ),
            );
      }

      await queue(
        id: 'operation-1',
        entityLocalId: 'payment-1',
        companyId: 'company-1',
      );
      await queue(
        id: 'operation-2',
        entityLocalId: 'payment-2',
        companyId: 'company-2',
      );

      final pushed = <String>[];
      final engine = SyncEngine(db: db, dio: Dio());
      engine.registerPusher('payment', (operation) async {
        pushed.add(operation.id);
        return SyncPushResult(remoteId: operation.entityLocalId);
      });

      expect(await engine.runPushCycle(companyId: 'company-1'), 1);
      expect(pushed, ['operation-1']);

      final payment = await (db.select(
        db.payments,
      )..where((row) => row.localId.equals('payment-1'))).getSingle();
      expect(payment.syncStatus, SyncStatus.synced.name);
      expect(payment.isDirty, isFalse);
      expect(payment.lastSyncedAt == null, isFalse);

      final otherOperation = await (db.select(
        db.syncOperations,
      )..where((row) => row.id.equals('operation-2'))).getSingle();
      expect(otherOperation.status, SyncStatus.pending.name);
    },
  );
}
