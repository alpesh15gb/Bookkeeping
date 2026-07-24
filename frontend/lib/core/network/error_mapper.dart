/// Normalizes Dio errors into the app's [ApiError] type so repositories can
/// throw a single, well-defined exception regardless of failure origin.
library;

import 'package:dio/dio.dart';

import '../errors/api_error.dart';

/// Converts any [DioException] into a user-facing [ApiError].
ApiError toApiError(DioException err) {
  final response = err.response;
  if (response != null) {
    final data = response.data;
    // Dio may decode JSON to a Map; otherwise it's a String or bytes.
    Object? detail;
    if (data is Map<String, dynamic>) {
      detail = data['detail'] ?? data['message'] ?? data;
    } else {
      detail = data;
    }
    // For 5xx errors use the standard message rather than the server's
    // generic response body (which is often unhelpful).
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 500) {
      return ApiError.fromDetail(null, statusCode);
    }
    return ApiError.fromDetail(detail, statusCode);
  }

  // No HTTP response → connectivity / timeout / cancellation.
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return ApiError.network(
        'The request timed out. Check your connection and try again.',
      );
    case DioExceptionType.connectionError:
      return ApiError.network(
        'No internet connection. Please check your network and try again.',
      );
    case DioExceptionType.cancel:
      return ApiError.network('The request was cancelled.');
    case DioExceptionType.badCertificate:
      return ApiError.network('A secure connection could not be established.');
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      return ApiError.network(
        err.message?.isNotEmpty == true
            ? err.message!
            : 'Something went wrong. Please try again.',
      );
  }
}
