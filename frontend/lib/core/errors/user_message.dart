/// Converts any caught error into a user-facing message.
///
/// Rules:
///   * [ApiError] → its already-user-facing [ApiError.message].
///   * [AppException] → its [AppException.message] (without the runtime-type
///     prefix that `toString()` would leak into the UI).
///   * [String] → returned as-is.
///   * Anything else → a generic fallback. Internal type names and transport
///     details must not reach end users.
///
/// Screens should render `userFacingErrorMessage(err)` instead of
/// `err.toString()` so users never see internal class names.
library;

import '../errors/api_error.dart';
import '../errors/app_exception.dart';

String userFacingErrorMessage(Object error) {
  if (error is ApiError) return error.message;
  if (error is AppException) return error.message;
  if (error is String) return error;
  return 'Something went wrong. Please try again.';
}
