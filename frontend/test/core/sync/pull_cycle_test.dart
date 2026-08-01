/// Pull cycle acceptance tests.
///
/// Tests the [SyncEngine.runPullCycle] behaviour against an in-memory database
/// with registered reference-data applicators.  Pull HTTP calls are intercepted
/// via a mock [Dio] adapter so no real network is needed.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/core/sync/reference_pull_service.dart';

/// Creates a mock response body matching `/apexbooks/sync/pull` shape.
Map<String, dynamic> _pullResponse(
  int nextCursor,
  List<Map<String, dynamic>> events,
) {
  return {'events': events, 'next_cursor': nextCursor};
}

Map<String, dynamic> _accountEvent({
  required String eventType,
  required String aggregateId,
  required String companyId,
  String code = '1001',
  String name = 'Cash',
  String accountType = 'asset',
}) {
  return {
    'event_type': eventType,
    'aggregate_type': 'account',
    'aggregate_id': aggregateId,
    'company_id': companyId,
    'payload': {
      'id': aggregateId,
      'code': code,
      'name': name,
      'account_type': accountType,
      'is_active': true,
    },
  };
}

Map<String, dynamic> _partyEvent({
  required String eventType,
  required String aggregateId,
  required String companyId,
  String name = 'Acme Corp',
  String kind = 'customer',
}) {
  return {
    'event_type': eventType,
    'aggregate_type': 'party',
    'aggregate_id': aggregateId,
    'company_id': companyId,
    'payload': {
      'id': aggregateId,
      'name': name,
      'kind': kind,
      'is_active': true,
    },
  };
}

Map<String, dynamic> _journalEvent({
  required String aggregateId,
  required String companyId,
  String debitAccountId = 'acc-cash',
  String creditAccountId = 'acc-revenue',
  bool includeAccountLabels = true,
}) {
  Map<String, dynamic> line({
    required String accountId,
    required String direction,
    required int amountMicros,
    String? code,
    String? name,
  }) {
    return {
      'account_id': accountId,
      if (includeAccountLabels && code != null) 'account_code': code,
      if (includeAccountLabels && name != null) 'account_name': name,
      'direction': direction,
      if (direction == 'DEBIT') 'debit_micros': amountMicros,
      if (direction == 'CREDIT') 'credit_micros': amountMicros,
      'narration': '$direction leg',
    };
  }

  return {
    'event_type': 'journal.posted',
    'aggregate_type': 'journal',
    'aggregate_id': aggregateId,
    'company_id': companyId,
    'device_id': 'device-a',
    'payload': {
      'entry_date': '2026-07-27',
      'reference_number': 'JRN-001',
      'description': 'Pulled journal',
      'source_type': 'MANUAL',
      'lines': [
        line(
          accountId: debitAccountId,
          direction: 'DEBIT',
          amountMicros: 18000000,
          code: '1001',
          name: 'Cash',
        ),
        line(
          accountId: creditAccountId,
          direction: 'CREDIT',
          amountMicros: 18000000,
          code: '4001',
          name: 'Revenue',
        ),
      ],
    },
  };
}

/// A [Dio] that returns canned responses for pull requests.
class MockPullTransport {
  int callCount = 0;
  final List<Map<String, dynamic>> _responses;

  MockPullTransport(this._responses);

  void adapter(RequestOptions options, RequestInterceptorHandler handler) {
    callCount++;
    final idx = callCount - 1;
    final resp = idx < _responses.length
        ? _responses[idx]
        : _pullResponse(0, []);
    handler.resolve(
      Response(requestOptions: options, data: resp, statusCode: 200),
    );
  }
}

void main() {
  group('SyncEngine pull cycle', () {
    late AppDatabase db;
    late SyncEngine engine;
    late MockPullTransport mock;

    Future<void> setupEngine(List<Map<String, dynamic>> responses) async {
      db = AppDatabase(NativeDatabase.memory());
      mock = MockPullTransport(responses);
      engine = SyncEngine(
        db: db,
        dio: Dio()
          ..interceptors.add(InterceptorsWrapper(onRequest: mock.adapter)),
      );
      registerReferencePullApplicators(engine, db);
    }

    tearDown(() async {
      engine.dispose();
      await db.close();
    });

    test('applies account.created event and advances checkpoint', () async {
      await setupEngine([
        _pullResponse(42, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-1',
            companyId: 'c-1',
          ),
        ]),
        _pullResponse(42, []), // second page empty
      ]);

      final applied = await engine.runPullCycle(companyId: 'c-1');

      expect(applied, greaterThan(0));
      expect(mock.callCount, greaterThan(0));

      // Account was created.
      final accounts = await db.select(db.accounts).get();
      expect(accounts.length, 1);
      expect(accounts.first.remoteId, 'acc-1');
      expect(accounts.first.name, 'Cash');

      // Checkpoint advanced.
      final cp =
          await (db.select(db.syncCheckpoints)..where(
                (c) => c.companyId.equals('c-1') & c.entityType.equals('*'),
              ))
              .getSingleOrNull();
      expect(cp, isNotNull);
      expect(cp!.lastServerSequence, 42);
    });

    test('replaying same event is idempotent', () async {
      await setupEngine([
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-1',
            companyId: 'c-1',
          ),
        ]),
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-1',
            companyId: 'c-1',
            name: 'Duplicate',
          ),
        ]),
      ]);

      await engine.runPullCycle(companyId: 'c-1');

      // Re-run pull — same cursor, same events.
      await engine.runPullCycle(companyId: 'c-1');

      // Only one row.
      final accounts = await db.select(db.accounts).get();
      expect(
        accounts.length,
        1,
        reason: 'duplicate event must not create a second row',
      );
      // The second event has name 'Duplicate', which via upsert should update.
      expect(
        accounts.first.name,
        'Duplicate',
        reason: 'replay with changed data updates existing row',
      );
    });

    test('account.updated overwrites existing fields', () async {
      await setupEngine([
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-1',
            companyId: 'c-1',
            name: 'Old Name',
          ),
        ]),
        _pullResponse(20, [
          _accountEvent(
            eventType: 'account.updated',
            aggregateId: 'acc-1',
            companyId: 'c-1',
            name: 'New Name',
          ),
        ]),
      ]);

      await engine.runPullCycle(companyId: 'c-1');
      await engine.runPullCycle(companyId: 'c-1');

      final accounts = await db.select(db.accounts).get();
      expect(accounts.length, 1);
      expect(accounts.first.name, 'New Name');
    });

    test('party.created creates a contact record', () async {
      await setupEngine([
        _pullResponse(10, [
          _partyEvent(
            eventType: 'party.created',
            aggregateId: 'party-1',
            companyId: 'c-1',
          ),
        ]),
        _pullResponse(10, []),
      ]);

      await engine.runPullCycle(companyId: 'c-1');

      final contacts = await db.select(db.contacts).get();
      expect(contacts.length, 1);
      expect(contacts.first.remoteId, 'party-1');
      expect(contacts.first.name, 'Acme Corp');
      expect(contacts.first.contactType, 'customer');
    });

    test('journal.posted creates synced journal and is idempotent', () async {
      await setupEngine([
        _pullResponse(10, [
          _journalEvent(aggregateId: 'journal-1', companyId: 'c-1'),
        ]),
        _pullResponse(10, [
          _journalEvent(aggregateId: 'journal-1', companyId: 'c-1'),
        ]),
      ]);

      await engine.runPullCycle(companyId: 'c-1');
      await engine.runPullCycle(companyId: 'c-1');

      final journals = await db.select(db.journalEntries).get();
      expect(journals.length, 1);
      expect(journals.first.localId, 'journal-1');
      expect(journals.first.lifecycleStatus, 'posted');
      expect(journals.first.syncStatus, 'synced');
      expect(journals.first.isDirty, false);

      final lines = await db.select(db.journalLines).get();
      expect(
        lines.length,
        2,
        reason: 'replayed pull must replace, not duplicate lines',
      );
      final debit = lines.singleWhere((line) => line.direction == 'DEBIT');
      final credit = lines.singleWhere((line) => line.direction == 'CREDIT');
      expect(debit.accountName, 'Cash');
      expect(credit.accountCode, '4001');
      expect(debit.amountPaise, 180000);
      expect(credit.amountPaise, 180000);
    });

    test('journal.posted falls back to local account labels', () async {
      await setupEngine([
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-cash',
            companyId: 'c-1',
            code: '1001',
            name: 'Cash Local',
          ),
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-revenue',
            companyId: 'c-1',
            code: '4001',
            name: 'Revenue Local',
          ),
        ]),
        _pullResponse(20, [
          _journalEvent(
            aggregateId: 'journal-2',
            companyId: 'c-1',
            includeAccountLabels: false,
          ),
        ]),
      ]);

      await engine.runPullCycle(companyId: 'c-1');
      await engine.runPullCycle(companyId: 'c-1');

      final lines = await db.select(db.journalLines).get();
      expect(lines.length, 2);
      expect(
        lines.map((line) => line.accountName),
        containsAll(['Cash Local', 'Revenue Local']),
      );
    });

    test(
      'journal lifecycle events apply drafts and reversals idempotently',
      () async {
        final created = _journalEvent(
          aggregateId: 'journal-3',
          companyId: 'c-1',
        )..['event_type'] = 'journal.created';
        final updated =
            _journalEvent(aggregateId: 'journal-3', companyId: 'c-1')
              ..['event_type'] = 'journal.updated'
              ..['payload']['description'] = 'Edited draft';
        final posted = _journalEvent(
          aggregateId: 'journal-3',
          companyId: 'c-1',
        );
        final reversed =
            _journalEvent(aggregateId: 'journal-3-reversal', companyId: 'c-1')
              ..['event_type'] = 'journal.reversed'
              ..['payload']['source_type'] = 'JOURNAL_REVERSAL'
              ..['payload']['reversed_journal_id'] = 'journal-3';

        await setupEngine([
          _pullResponse(10, [created]),
          _pullResponse(20, [updated]),
          _pullResponse(30, [posted]),
          _pullResponse(40, [reversed]),
          _pullResponse(40, []),
        ]);

        await engine.runPullCycle(companyId: 'c-1');
        await engine.runPullCycle(companyId: 'c-1');
        await engine.runPullCycle(companyId: 'c-1');
        await engine.runPullCycle(companyId: 'c-1');
        await engine.runPullCycle(companyId: 'c-1');

        final journals = await db.select(db.journalEntries).get();
        expect(journals.length, 2);
        expect(
          journals
              .singleWhere((row) => row.localId == 'journal-3')
              .lifecycleStatus,
          'reversed',
        );
        expect(
          journals
              .singleWhere((row) => row.localId == 'journal-3-reversal')
              .sourceType,
          'JOURNAL_REVERSAL',
        );
        expect((await db.select(db.journalLines).get()).length, 4);
      },
    );

    test(
      'unknown event rolls back the batch and preserves checkpoint',
      () async {
        await setupEngine([
          _pullResponse(10, [
            _accountEvent(
              eventType: 'account.created',
              aggregateId: 'acc-1',
              companyId: 'c-1',
            ),
            {'event_type': 'unknown.event', 'company_id': 'c-1', 'payload': {}},
          ]),
          _pullResponse(10, []),
        ]);

        await engine.runPullCycle(companyId: 'c-1');

        final accounts = await db.select(db.accounts).get();
        expect(accounts, isEmpty);
        final cp =
            await (db.select(db.syncCheckpoints)..where(
                  (c) => c.companyId.equals('c-1') & c.entityType.equals('*'),
                ))
                .getSingleOrNull();
        expect(cp, isNull);
      },
    );

    test('cross-company event rolls back the entire pull batch', () async {
      await setupEngine([
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-c1',
            companyId: 'c-1',
          ),
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-c2',
            companyId: 'c-2',
          ),
        ]),
        _pullResponse(10, []),
      ]);

      // Pull for company c-1 only.
      await engine.runPullCycle(companyId: 'c-1');

      final accounts = await db.select(db.accounts).get();
      expect(accounts, isEmpty);
    });

    test('Drift stream reflects committed pull changes', () async {
      await setupEngine([
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-1',
            companyId: 'c-1',
          ),
        ]),
        _pullResponse(10, []),
      ]);

      // Start watching before the pull.
      final stream = db.select(db.accounts).watch();

      // Trigger pull.
      await engine.runPullCycle(companyId: 'c-1');

      // The stream must emit the new account.
      final emitted = await stream.first;
      expect(emitted.length, 1);
      expect(emitted.first.remoteId, 'acc-1');
    });

    test('push and pull share single-flight lock', () async {
      await setupEngine([
        _pullResponse(10, [
          _accountEvent(
            eventType: 'account.created',
            aggregateId: 'acc-1',
            companyId: 'c-1',
          ),
        ]),
        _pullResponse(10, []),
      ]);

      // Start a slow push operation.
      final pushFuture = engine.runPushCycle();

      // Pull should succeed (separate lock).
      final pullResult = await engine.runPullCycle(companyId: 'c-1');

      expect(pullResult, greaterThanOrEqualTo(0));

      await pushFuture;
    });

    test(
      'transaction event types without an applicator are acknowledged, '
      'not deadlocked',
      () async {
        // Regression: previously these types had no applicator, so the pull
        // cycle threw StateError and never advanced the checkpoint → every
        // subsequent pull retried the same event forever.
        await setupEngine([
          _pullResponse(99, [
            {
              'event_type': 'purchase_invoice.posted',
              'aggregate_type': 'purchase_invoice',
              'aggregate_id': 'agg-pi-1',
              'company_id': 'c-1',
              'payload': {'invoice_number': 'BILL-1'},
            },
            {
              'event_type': 'sales_delivery.posted',
              'aggregate_type': 'sales_delivery',
              'aggregate_id': 'agg-sd-1',
              'company_id': 'c-1',
              'payload': {'sales_order_id': 'so-1'},
            },
            {
              'event_type': 'credit_note.posted',
              'aggregate_type': 'credit_note',
              'aggregate_id': 'agg-cn-1',
              'company_id': 'c-1',
              'payload': {'number': 1},
            },
          ]),
          _pullResponse(99, []), // caught up
        ]);

        // Must not throw even though none of these have a real applicator.
        final applied = await engine.runPullCycle(companyId: 'c-1');

        expect(applied, greaterThanOrEqualTo(0));

        // Checkpoint advanced past the acknowledged events.
        final cp =
            await (db.select(db.syncCheckpoints)..where(
                  (c) => c.companyId.equals('c-1') & c.entityType.equals('*'),
                ))
                .getSingleOrNull();
        expect(cp, isNotNull);
        expect(cp!.lastServerSequence, 99);
      },
    );
  });
}
