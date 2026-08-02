/// Sealed result type used across the data layer to model the four states an
/// asynchronous operation can be in: loading, success (with data), or failure
/// (with an [ApiError]). This keeps presentation code branch-complete and
/// avoids the common `AsyncSnapshot` pitfalls.
library;

import '../errors/api_error.dart';

export '../errors/api_error.dart' show ApiError;

sealed class Result<T> {
  const Result();
}

/// The operation is in progress and no data is available yet.
final class Loading<T> extends Result<T> {
  const Loading();
}

/// The operation completed successfully with [value].
final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

/// The operation failed with [error].
final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final ApiError error;
}

/// Convenience helpers for working with [Result] values.
extension ResultX<T> on Result<T> {
  /// `true` while the operation is running.
  bool get isLoading => this is Loading<T>;

  /// `true` when the operation completed with data.
  bool get isSuccess => this is Success<T>;

  /// `true` when the operation completed with an error.
  bool get isFailure => this is Failure<T>;

  /// The data, or `null` if not [Success].
  T? get dataOrNull => switch (this) {
    Success<T>(:final value) => value,
    _ => null,
  };

  /// The error, or `null` if not [Failure].
  ApiError? get errorOrNull => switch (this) {
    Failure<T>(:final error) => error,
    _ => null,
  };

  /// Returns the value on success, or throws the error on failure.
  T getOrThrow() => switch (this) {
    Success<T>(:final value) => value,
    Failure<T>(:final error) => throw error,
    Loading<T>() => throw StateError('Result is still loading'),
  };
}

/// Generic alias for an async provider that emits a [Result].
typedef AsyncResult<T> = Future<Result<T>>;
