/// Tests for [SyncRetryPolicy].
library;

import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/sync/sync_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = SyncRetryPolicy(
    maxAttempts: 5,
    baseDelaySeconds: 10,
    maxDelaySeconds: 120,
    jitterFraction: 0.0, // no jitter for deterministic tests
  );

  group('SyncRetryPolicy.decide', () {
    test('RetryableSyncException → retry', () {
      expect(
        policy.decide(const RetryableSyncException('timeout'), attemptCount: 0),
        RetryDecision.retry,
      );
    });

    test('PermanentSyncException → permanent', () {
      expect(
        policy.decide(
          const PermanentSyncException('validation failed'),
          attemptCount: 0,
        ),
        RetryDecision.permanent,
      );
    });

    test('ConflictException → permanent', () {
      expect(
        policy.decide(const ConflictException('conflict'), attemptCount: 0),
        RetryDecision.permanent,
      );
    });

    test('NetworkUnavailableException → retry', () {
      expect(
        policy.decide(const NetworkUnavailableException(), attemptCount: 0),
        RetryDecision.retry,
      );
    });

    test('exceeding maxAttempts → permanent', () {
      expect(
        policy.decide(
          const RetryableSyncException('timeout'),
          attemptCount: 5,
        ), // equal to maxAttempts
        RetryDecision.permanent,
      );
    });
  });

  group('SyncRetryPolicy.decideStatusCode', () {
    for (final code in [408, 429, 500, 502, 503, 504]) {
      test('HTTP $code → retry', () {
        expect(
          policy.decideStatusCode(code, attemptCount: 0),
          RetryDecision.retry,
        );
      });
    }
    for (final code in [400, 401, 403, 404, 422]) {
      test('HTTP $code → permanent', () {
        expect(
          policy.decideStatusCode(code, attemptCount: 0),
          RetryDecision.permanent,
        );
      });
    }
  });

  group('SyncRetryPolicy.nextAttemptAt', () {
    test('increases with attempt count', () {
      final t0 = policy.nextAttemptAt(0);
      final t1 = policy.nextAttemptAt(1);
      final t2 = policy.nextAttemptAt(2);
      expect(t1.isAfter(t0), true);
      expect(t2.isAfter(t1), true);
    });

    test('respects maxDelay cap', () {
      // After many attempts the delay should not exceed maxDelaySeconds.
      final farFuture = policy.nextAttemptAt(20);
      final maxAllowed = DateTime.now().toUtc().add(
        const Duration(seconds: 130), // max + small buffer
      );
      expect(farFuture.isBefore(maxAllowed), true);
    });

    test('retryAfterSeconds hint is honoured', () {
      const hint = 60;
      final t = policy.nextAttemptAt(0, retryAfterSeconds: hint);
      final expected = DateTime.now().toUtc().add(
        const Duration(seconds: hint),
      );
      // Allow ±2s for test execution time.
      expect(t.difference(expected).inSeconds.abs(), lessThan(2));
    });
  });
}
