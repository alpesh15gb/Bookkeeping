import 'dart:convert';

import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/sync/sync_operation.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/features/journals/data/remote/journal_remote_data_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

OutboxRecord _op() => OutboxRecord(
  id: 'op-1',
  entityType: 'journal',
  entityLocalId: 'journal-1',
  companyId: 'company-1',
  actorId: 'actor-1',
  deviceId: 'device-1',
  operationType: 'post',
  payload: jsonEncode({
    'event_id': 'event-1',
    'aggregate_id': 'journal-1',
    'event_type': 'journal.posted',
  }),
  idempotencyKey: 'journal:post:journal-1',
  priority: 0,
  attemptCount: 0,
  status: SyncStatus.pending,
  createdAt: DateTime.utc(2026, 7, 27),
);

Dio _dioReturning(Object? body) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: body),
      ),
    ),
  );
  return dio;
}

void main() {
  group('journalPusher acknowledgement contract', () {
    test('accepts current acknowledgements response', () async {
      final result = await journalPusher(
        _op(),
        _dioReturning({
          'acknowledgements': [
            {'event_id': 'event-1', 'server_sequence': 42, 'duplicate': false},
          ],
        }),
      );

      expect(result.remoteId, 'journal-1');
    });

    test('accepts legacy acknowledged response', () async {
      final result = await journalPusher(
        _op(),
        _dioReturning({
          'acknowledged': [
            {'event_id': 'event-1', 'server_sequence': 42, 'duplicate': true},
          ],
        }),
      );

      expect(result.remoteId, 'journal-1');
    });

    test(
      'surfaces acknowledgement processing errors as permanent failures',
      () async {
        await expectLater(
          journalPusher(
            _op(),
            _dioReturning({
              'acknowledgements': [
                {
                  'event_id': 'event-1',
                  'server_sequence': 42,
                  'duplicate': false,
                  'error': 'Each line must have a non-zero amount',
                },
              ],
            }),
          ),
          throwsA(isA<PermanentSyncException>()),
        );
      },
    );

    test('surfaces immutable journal acknowledgement as a conflict', () async {
      await expectLater(
        journalPusher(
          _op(),
          _dioReturning({
            'acknowledgements': [
              {
                'event_id': 'event-1',
                'server_sequence': 43,
                'duplicate': false,
                'error':
                    'Posted journal entries are immutable; create a reversal instead.',
              },
            ],
          }),
        ),
        throwsA(isA<ConflictException>()),
      );
    });

    test(
      'rejects malformed response instead of falling back silently',
      () async {
        await expectLater(
          journalPusher(
            _op(),
            _dioReturning({
              'acknowledgements': {'bad': true},
            }),
          ),
          throwsA(isA<ContractException>()),
        );
      },
    );
  });
}
