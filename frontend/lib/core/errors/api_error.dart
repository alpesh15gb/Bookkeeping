/// A normalized, user-facing error type that wraps every backend failure.
///
/// The ApexBooks backend returns errors in several shapes:
///   * `{"detail": "human readable message"}` (most endpoints)
///   * `{"detail": [ {loc, msg, type}, ... ]}` (Pydantic 422 validation)
///   * `{"error": "Rate limit exceeded.", "detail": "10 per 1 minute"}` (429)
///
/// [ApiError] collapses all of these into a single [message] suitable for a
/// SnackBar/dialog, plus structured fields the UI can inspect (status code,
/// whether it is a validation error, and a map of field-level messages).
class ApiError implements Exception {
  const ApiError({
    required this.message,
    this.statusCode,
    this.isValidationError = false,
    this.fieldErrors = const {},
    this.type,
  });

  /// Human-readable summary shown directly to the user.
  final String message;

  /// The HTTP status code returned by the server, if any.
  final int? statusCode;

  /// `true` for 422 Pydantic validation failures.
  final bool isValidationError;

  /// Field-keyed validation messages derived from a 422 response. Keys mirror
  /// the last element of each `loc` segment (e.g. `email`, `line_items.0.rate`).
  final Map<String, String> fieldErrors;

  /// The raw error `type` reported by the backend (Pydantic error code), if any.
  final String? type;

  /// `true` when the request was rejected because the access token expired.
  bool get isUnauthorized => statusCode == 401;

  /// `true` when the user lacks permission for the resource.
  bool get isForbidden => statusCode == 403;

  /// `true` when the requested resource does not exist.
  bool get isNotFound => statusCode == 404;

  /// `true` when the request was rate-limited.
  bool get isRateLimited => statusCode == 429;

  /// `true` for transient server errors worth retrying.
  bool get isServer => statusCode != null && statusCode! >= 500;

  /// `true` when the server returned a response that did not match the
  /// invoice/API contract.
  bool get isInvalidResponse => type == 'invalid_response';

  /// `true` for connectivity / timeout / socket errors (no HTTP response).
  bool get isNetwork => statusCode == null && !isInvalidResponse;

  @override
  String toString() => message;

  /// Builds an [ApiError] from a parsed JSON `detail` payload and status code.
  factory ApiError.fromDetail(
    Object? detail,
    int statusCode, {
    String? errorLabel,
  }) {
    // Pydantic validation array: [{"loc": [...], "msg": "...", "type": "..."}]
    if (detail is List) {
      final fields = <String, String>{};
      final messages = <String>[];
      for (final item in detail) {
        if (item is Map) {
          final loc = item['loc'];
          String field = '';
          if (loc is List && loc.isNotEmpty) {
            final segments = loc
                .skip(1) // drop the leading "body" segment
                .map((e) => e.toString())
                .toList(growable: false);
            field = segments.join('.');
          }
          final msg = (item['msg'] ?? 'Invalid value').toString();
          if (field.isNotEmpty) {
            fields[field] = msg;
          }
          messages.add(field.isEmpty ? msg : '$field: $msg');
        }
      }
      return ApiError(
        message: messages.isEmpty
            ? 'Please correct the highlighted fields and try again.'
            : messages.join('\n'),
        statusCode: statusCode,
        isValidationError: true,
        fieldErrors: fields,
        type: errorLabel,
      );
    }

    // Standard {"detail": "..."} object.
    if (detail is String && detail.isNotEmpty) {
      return ApiError(
        message: detail,
        statusCode: statusCode,
        type: errorLabel,
      );
    }

    // Rate limit shape: {"error": "...", "detail": "..."}.
    if (detail is Map && detail['detail'] is String) {
      return ApiError(
        message: detail['detail'].toString(),
        statusCode: statusCode,
        type: detail['error']?.toString(),
      );
    }

    return ApiError(
      message: _defaultMessage(statusCode),
      statusCode: statusCode,
      type: errorLabel,
    );
  }

  /// Builds an [ApiError] for a non-HTTP failure (timeout, socket, etc.).
  factory ApiError.network(String message) =>
      ApiError(message: message, statusCode: null);

  static String _defaultMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'The request could not be processed. Please check your input.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to perform this action.';
      case 404:
        return 'The requested record could not be found.';
      case 409:
        return 'This record already exists or conflicts with another.';
      case 422:
        return 'Some fields need your attention before continuing.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The server is unavailable. Please try again shortly.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
