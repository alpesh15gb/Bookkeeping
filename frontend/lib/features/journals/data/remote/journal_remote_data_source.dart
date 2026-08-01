/// Remote data source for journal entries.
///
/// This is the only file that calls the backend sync API for journals.
/// It wraps the existing [JournalService] call pattern and is only invoked
/// by the [SyncEngine], never directly by the UI.
///
/// All amounts are encoded via [Money.toBackendMicros] before sending.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/sync/sync_operation.dart';
import '../../../../core/sync/sync_engine.dart';

/// Handles the push of a `journal` outbox operation to the server.
///
/// Called by [SyncEngine] via the registered pusher for `'journal'`.
Future<SyncPushResult> journalPusher(OutboxRecord op, Dio dio) async {
  final payload = jsonDecode(op.payload) as Map<String, dynamic>;

  try {
    final res = await dio.post(
      '/apexbooks/sync/push',
      data: {
        'events': [payload],
      },
      options: Options(headers: {'Idempotency-Key': op.idempotencyKey}),
    );

    final rawBody = res.data;
    if (rawBody is! Map<String, dynamic>) {
      throw const ContractException(
        'Server returned malformed journal push response.',
      );
    }
    final hasCurrentAcks = rawBody.containsKey('acknowledgements');
    final hasLegacyAcks = rawBody.containsKey('acknowledged');
    final rawAcks = hasCurrentAcks
        ? rawBody['acknowledgements']
        : (hasLegacyAcks ? rawBody['acknowledged'] : null);
    if (rawAcks is! List) {
      throw const ContractException(
        'Server journal push response is missing acknowledgements.',
      );
    }

    if (rawAcks.isEmpty) {
      throw PermanentSyncException(
        'Server returned empty acknowledgement for journal push.',
        statusCode: res.statusCode,
      );
    }

    final firstAck = rawAcks.first;
    if (firstAck is! Map<String, dynamic>) {
      throw const ContractException(
        'Server returned malformed journal push acknowledgement.',
      );
    }
    final ack = firstAck;

    // If the event was rejected by the handler, surface the error.
    final errorMsg = ack['error']?.toString();
    if (errorMsg != null && errorMsg.isNotEmpty) {
      final normalizedError = errorMsg.toLowerCase();
      if (normalizedError.contains('immutable') ||
          normalizedError.contains('conflict') ||
          normalizedError.contains('already reversed')) {
        throw ConflictException(
          errorMsg,
          conflictId: payload['aggregate_id']?.toString(),
        );
      }
      // "active FY not found" and similar accounting-period errors are permanent.
      throw PermanentSyncException(
        errorMsg,
        statusCode: 422,
        userAction: 'Check that a current financial year exists for this date.',
      );
    }

    // The server doesn't return the final entity UUID in push-acks today;
    // we use the event_id (== localId) as a stable correlation key.
    // The remote UUID will be populated on the next pull cycle.
    return SyncPushResult(
      remoteId:
          ack['entity_id']?.toString() ??
          payload['aggregate_id']?.toString() ??
          ack['event_id']?.toString() ??
          '',
      serverTimestamp: DateTime.tryParse(ack['received_at']?.toString() ?? ''),
    );
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    if (code != null) {
      if (code == 429) {
        final retryAfter = int.tryParse(
          e.response?.headers.value('retry-after') ?? '',
        );
        throw RetryableSyncException(
          'Rate limited by server.',
          statusCode: code,
          retryAfterSeconds: retryAfter,
        );
      }
      if (code == 400 || code == 422) {
        final body = e.response?.data;
        final msg = body is Map
            ? (body['detail'] ?? body['message'] ?? 'Validation error')
            : 'Validation error';
        throw PermanentSyncException(
          msg.toString(),
          statusCode: code,
          userAction: 'Review the journal entry for errors and correct it.',
        );
      }
      if (code == 409) {
        throw ConflictException(
          'Journal entry conflicts with a remote version.',
          conflictId: payload['aggregate_id']?.toString(),
        );
      }
      if (code >= 500) {
        throw RetryableSyncException(
          'Server error ($code). Will retry.',
          statusCode: code,
        );
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      throw RetryableSyncException('Network error. Will retry.', cause: e);
    }
    rethrow;
  }
}
