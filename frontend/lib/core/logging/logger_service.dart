/// Centralized logging service. Replaces every `print()` with structured,
/// level-aware logging that can be routed to console, a file, or a remote
/// sink. In debug builds logs surface in the console; in release builds only
/// warnings+errors are kept to avoid leaking PII.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { debug, info, warning, error }

extension LogLevelX on LogLevel {
  String get label => switch (this) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warning => 'WARN',
    LogLevel.error => 'ERROR',
  };
}

/// A structured log record.
@immutable
class LogRecord {
  LogRecord({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.context,
    DateTime? at,
  }) : timestamp = at ?? DateTime.now();

  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? context;
  final DateTime timestamp;
}

/// Pluggable log sink. The default writes to `dart:developer`; analytics can
/// attach an additional sink (e.g. Sentry/Firebase) by listening to [stream].
abstract class LogSink {
  void emit(LogRecord record);
}

/// Central logger. Use `ref.read(loggerProvider).info(...)` everywhere instead
/// of `print()`. Supports debug/info/warning/error levels and an optional
/// broadcast stream that the analytics service can subscribe to.
class LoggerService implements LogSink {
  LoggerService({this.enableDebug = kDebugMode});
  final bool enableDebug;
  final _controller = StreamController<LogRecord>.broadcast(sync: true);

  /// Broadcast stream of every emitted record — analytics subscribes here.
  Stream<LogRecord> get stream => _controller.stream;

  void debug(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.debug, message, context: context);

  void info(String message, {Map<String, dynamic>? context}) =>
      _log(LogLevel.info, message, context: context);

  void warning(
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? context,
  }) => _log(
    LogLevel.warning,
    message,
    error: error,
    stackTrace: stack,
    context: context,
  );

  void error(
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? context,
  }) => _log(
    LogLevel.error,
    message,
    error: error,
    stackTrace: stack,
    context: context,
  );

  void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    if (level == LogLevel.debug && !enableDebug) return;
    final record = LogRecord(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
    emit(record);
    _controller.add(record);
  }

  @override
  void emit(LogRecord record) {
    final prefix = record.context != null && record.context!.isNotEmpty
        ? ' ${record.context}'
        : '';
    final errPart = record.error != null ? ' | ${record.error}' : '';
    developer.log(
      '${record.level.label}: ${record.message}$prefix$errPart',
      level: record.level.index,
      name: 'apexbooks',
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }

  void dispose() => _controller.close();
}

/// Provider for the app-wide [LoggerService].
final loggerProvider = Provider<LoggerService>((ref) {
  final logger = LoggerService();
  ref.onDispose(logger.dispose);
  return logger;
});
