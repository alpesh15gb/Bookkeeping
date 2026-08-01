/// Retry policy for the sync engine.
///
/// Classifies HTTP status codes and exception types into retryable vs.
/// permanent failures, and computes the next retry delay using exponential
/// backoff with jitter.
library;

import 'dart:math';

import '../errors/app_exception.dart';

/// Decides how the sync engine should react to a failure.
enum RetryDecision {
  /// Keep retrying with backoff.
  retry,

  /// Stop retrying — user action is required.
  permanent,
}

class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.maxAttempts = 10,
    this.baseDelaySeconds = 30,
    this.maxDelaySeconds = 300,
    this.jitterFraction = 0.20,
  });

  /// Maximum number of attempts before an operation is marked as [permanent].
  final int maxAttempts;

  /// Initial delay in seconds for the first retry (attempt 1 → attempt 2).
  final int baseDelaySeconds;

  /// Maximum delay cap in seconds.
  final int maxDelaySeconds;

  /// ±fraction of jitter to add/subtract from the computed delay.
  final double jitterFraction;

  static final _rng = Random();

  // ── Retryable HTTP status codes ───────────────────────────────────────────

  static const _retryableStatusCodes = {
    408, // Request Timeout
    429, // Too Many Requests
    500, // Internal Server Error
    502, // Bad Gateway
    503, // Service Unavailable
    504, // Gateway Timeout
  };

  static const _permanentStatusCodes = {
    400, // Bad Request — validation error that won't change
    401, // Unauthorised — session expired; refresh interceptor already tried
    403, // Forbidden — wrong permissions
    404, // Not Found — required remote dependency missing
    409, // Conflict — detected as a [ConflictException], not a retry
    422, // Unprocessable Entity — schema/validation mismatch
  };

  // ── Decision ──────────────────────────────────────────────────────────────

  /// Returns the appropriate [RetryDecision] for [exception], taking
  /// [attemptCount] into account.
  RetryDecision decide(Object exception, {required int attemptCount}) {
    if (attemptCount >= maxAttempts) return RetryDecision.permanent;

    if (exception is RetryableSyncException) return RetryDecision.retry;
    if (exception is PermanentSyncException) return RetryDecision.permanent;
    if (exception is ConflictException) return RetryDecision.permanent;
    if (exception is ContractException) return RetryDecision.permanent;
    if (exception is AuthorizationException) return RetryDecision.permanent;
    if (exception is ValidationException) return RetryDecision.permanent;

    if (exception is RetryableSyncException) {
      final code = exception.statusCode;
      if (code != null && _permanentStatusCodes.contains(code)) {
        return RetryDecision.permanent;
      }
      return RetryDecision.retry;
    }

    // Network-level errors (no response) are always retryable.
    if (exception is NetworkUnavailableException) return RetryDecision.retry;

    return RetryDecision.retry;
  }

  /// Classifies an HTTP status code into a [RetryDecision].
  RetryDecision decideStatusCode(int statusCode, {required int attemptCount}) {
    if (attemptCount >= maxAttempts) return RetryDecision.permanent;
    if (_retryableStatusCodes.contains(statusCode)) return RetryDecision.retry;
    if (_permanentStatusCodes.contains(statusCode)) {
      return RetryDecision.permanent;
    }
    // Unknown codes: treat as retryable to be safe.
    return RetryDecision.retry;
  }

  // ── Delay computation ─────────────────────────────────────────────────────

  /// Computes the next [DateTime] at which the operation may be retried.
  ///
  /// Uses exponential backoff: `min(maxDelay, base * 2^attemptCount)` plus
  /// ±[jitterFraction] random jitter.
  DateTime nextAttemptAt(int attemptCount, {int? retryAfterSeconds}) {
    final now = DateTime.now().toUtc();

    if (retryAfterSeconds != null) {
      return now.add(Duration(seconds: retryAfterSeconds));
    }

    // Capped exponential: 30s, 60s, 120s, 240s, 300s, 300s, …
    final base = (baseDelaySeconds * pow(2, attemptCount).toInt()).clamp(
      0,
      maxDelaySeconds,
    );

    // ±20% jitter
    final jitter = (_rng.nextDouble() * 2 - 1) * jitterFraction * base;
    final delay = (base + jitter).round().clamp(1, maxDelaySeconds);

    return now.add(Duration(seconds: delay));
  }
}
