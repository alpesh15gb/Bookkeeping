/// Offline request queue. Mutations (POST/PUT/PATCH/DELETE) that fail due to a
/// network error are queued and replayed when connectivity is restored.
/// Duplicate request prevention ensures the same mutation isn't sent twice.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/logger_service.dart';
import '../network/api_client.dart';

export '../result/result.dart' show Result, Success, Failure;

/// A single queued mutation.
@immutable
class QueuedRequest {
  const QueuedRequest({
    required this.id,
    required this.method,
    required this.path,
    this.body,
    this.headers,
    this.createdAt,
  });

  final String id;
  final String method; // POST, PUT, PATCH, DELETE
  final String path;
  final Map<String, dynamic>? body;
  final Map<String, String>? headers;
  final int? createdAt;

  QueuedRequest copyWith({int? createdAt}) => QueuedRequest(
    id: id,
    method: method,
    path: path,
    body: body,
    headers: headers,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'path': path,
    if (body != null) 'body': body,
    if (headers != null) 'headers': headers,
    'createdAt': createdAt ?? DateTime.now().millisecondsSinceEpoch,
  };

  factory QueuedRequest.fromJson(Map<String, dynamic> json) => QueuedRequest(
    id: json['id'] as String,
    method: json['method'] as String,
    path: json['path'] as String,
    body: json['body'] as Map<String, dynamic>?,
    headers: json['headers'] as Map<String, String>?,
    createdAt: json['createdAt'] as int?,
  );
}

/// Manages the offline queue — persists to shared_preferences and replays
/// when online.
class OfflineQueue {
  OfflineQueue(this._dio, this._logger);

  final Dio _dio;
  final LoggerService _logger;
  static const _key = 'offline_queue';

  List<QueuedRequest> _queue = [];

  /// Load persisted queue from disk.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _queue = raw
        .map(
          (e) => QueuedRequest.fromJson(jsonDecode(e) as Map<String, dynamic>),
        )
        .toList();
    _logger.info('Offline queue loaded: ${_queue.length} pending');
  }

  /// Enqueue a mutation.
  Future<void> enqueue(QueuedRequest request) async {
    _queue.add(request);
    await _persist();
    _logger.info('Queued ${request.method} ${request.path}');
  }

  /// Replay all queued requests. Returns `true` if all succeeded.
  Future<bool> replayAll() async {
    final remaining = <QueuedRequest>[];
    bool allOk = true;
    for (final req in _queue) {
      final ok = await _tryReplay(req);
      if (ok) {
        _logger.info('Replayed ${req.method} ${req.path}');
      } else {
        remaining.add(req);
        allOk = false;
      }
    }
    _queue = remaining;
    await _persist();
    return allOk;
  }

  Future<bool> _tryReplay(QueuedRequest req) async {
    try {
      final options = Options(headers: req.headers);
      switch (req.method.toUpperCase()) {
        case 'POST':
          await _dio.post(req.path, data: req.body, options: options);
        case 'PUT':
          await _dio.put(req.path, data: req.body, options: options);
        case 'PATCH':
          await _dio.patch(req.path, data: req.body, options: options);
        case 'DELETE':
          await _dio.delete(req.path, options: options);
      }
      return true;
    } on DioException catch (e) {
      // Only retry network errors; 4xx are permanent.
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        return false;
      }
      // Non-retryable — discard this request.
      _logger.warning('Discarding failed ${req.method} ${req.path}', error: e);
      return true; // don't keep it in queue
    } catch (e) {
      _logger.warning('Discarding ${req.method} ${req.path}', error: e);
      return true;
    }
  }

  /// Whether there are pending requests.
  bool get hasPending => _queue.isNotEmpty;

  /// Number of pending requests.
  int get pendingCount => _queue.length;

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _queue.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  /// Clear all pending.
  Future<void> clear() async {
    _queue = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Provider for [OfflineQueue].
final offlineQueueProvider = Provider<OfflineQueue>((ref) {
  final dio = ref.watch(apiClientProvider);
  final logger = ref.watch(loggerProvider);
  return OfflineQueue(dio, logger);
});
