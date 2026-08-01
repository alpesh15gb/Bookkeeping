/// Typed application exception hierarchy.
///
/// All exception types the application can raise are defined here.
/// Callers should catch a specific subclass rather than the parent
/// [AppException] wherever the distinction matters.
library;

/// Base class for all application-specific exceptions.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;

  /// The underlying error that triggered this exception, if any.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

// ── Validation ────────────────────────────────────────────────────────────────

/// A business rule or input constraint was violated.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause, this.fieldErrors});

  /// Per-field validation messages, keyed by field name.
  final Map<String, String>? fieldErrors;
}

// ── Local database ────────────────────────────────────────────────────────────

/// An operation on the local SQLite database failed.
final class LocalDatabaseException extends AppException {
  const LocalDatabaseException(super.message, {super.cause});
}

// ── Network ───────────────────────────────────────────────────────────────────

/// The device has no usable network path.
///
/// This is a hint only — the sync engine continues to queue operations and
/// will retry when connectivity appears to return.
final class NetworkUnavailableException extends AppException {
  const NetworkUnavailableException({super.cause})
    : super('No network connection available.');
}

// ── Authentication / authorisation ────────────────────────────────────────────

/// Authentication failed or the session has expired.
final class AuthenticationException extends AppException {
  const AuthenticationException(super.message, {super.cause});
}

/// The current user lacks permission for this operation.
final class AuthorizationException extends AppException {
  const AuthorizationException(super.message, {super.cause});
}

// ── Backend contract ──────────────────────────────────────────────────────────

/// The server returned a response that does not match the expected schema.
///
/// This is a non-retryable failure — no retry will change the schema.
final class ContractException extends AppException {
  const ContractException(super.message, {super.cause});
}

// ── Sync ─────────────────────────────────────────────────────────────────────

/// A sync operation failed but should be retried (transient error).
///
/// Examples: network timeout, HTTP 429, HTTP 503.
final class RetryableSyncException extends AppException {
  const RetryableSyncException(
    super.message, {
    super.cause,
    this.statusCode,
    this.retryAfterSeconds,
  });

  final int? statusCode;

  /// Hint from the server for how long to wait before retrying, in seconds.
  final int? retryAfterSeconds;
}

/// A sync operation failed permanently and must not be retried automatically.
///
/// Examples: HTTP 400 validation error, HTTP 404 for a required dependency,
/// accounting-period locked, invalid journal balance.
///
/// User action is required to resolve these.
final class PermanentSyncException extends AppException {
  const PermanentSyncException(
    super.message, {
    super.cause,
    this.statusCode,
    this.userAction,
  });

  final int? statusCode;

  /// A short, user-readable description of the action needed to unblock sync.
  final String? userAction;
}

/// A conflict was detected between local and remote versions of an entity.
///
/// Both versions are retained in the [SyncConflicts] outbox table.
/// The user must resolve the conflict before the operation can proceed.
final class ConflictException extends AppException {
  const ConflictException(super.message, {super.cause, this.conflictId});

  /// The ID of the [SyncConflict] row that was created during detection.
  final String? conflictId;
}

// ── Attachments ───────────────────────────────────────────────────────────────

/// A locally referenced attachment file cannot be found at its stored path.
final class AttachmentMissingException extends AppException {
  const AttachmentMissingException(
    super.message, {
    super.cause,
    this.localPath,
  });

  final String? localPath;
}
