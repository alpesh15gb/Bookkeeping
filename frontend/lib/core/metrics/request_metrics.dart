/// Request metrics — tracks endpoint, latency, success rate, retries, and payload
/// size for every API call. Useful for production debugging and performance
/// monitoring.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A snapshot of metrics for one endpoint.
@immutable
class EndpointMetrics {
  const EndpointMetrics({
    required this.endpoint,
    required this.count,
    required this.successCount,
    required this.totalLatencyMs,
    required this.retryCount,
    required this.totalPayloadBytes,
  });

  final String endpoint;
  final int count;
  final int successCount;
  final int retryCount;
  final int totalLatencyMs;
  final int totalPayloadBytes;

  double get successRate => count == 0 ? 1.0 : successCount / count;
  double get avgLatencyMs => count == 0 ? 0 : totalLatencyMs / count;
  double get avgPayloadBytes => count == 0 ? 0 : totalPayloadBytes / count;

  EndpointMetrics record({
    required bool success,
    required int latencyMs,
    int payloadBytes = 0,
    int retries = 0,
  }) => EndpointMetrics(
    endpoint: endpoint,
    count: count + 1,
    successCount: successCount + (success ? 1 : 0),
    totalLatencyMs: totalLatencyMs + latencyMs,
    retryCount: retryCount + retries,
    totalPayloadBytes: totalPayloadBytes + payloadBytes,
  );
}

/// Collects metrics for all endpoints.
class RequestMetricsCollector {
  final _metrics = LinkedHashMap<String, EndpointMetrics>();

  /// Record an API call.
  void record({
    required String endpoint,
    required bool success,
    required int latencyMs,
    int payloadBytes = 0,
    int retries = 0,
  }) {
    final current =
        _metrics[endpoint] ??
        EndpointMetrics(
          endpoint: endpoint,
          count: 0,
          successCount: 0,
          totalLatencyMs: 0,
          retryCount: 0,
          totalPayloadBytes: 0,
        );
    _metrics[endpoint] = current.record(
      success: success,
      latencyMs: latencyMs,
      payloadBytes: payloadBytes,
      retries: retries,
    );
  }

  /// All collected metrics.
  List<EndpointMetrics> get all => _metrics.values.toList();

  /// Metrics for a specific endpoint.
  EndpointMetrics? forEndpoint(String endpoint) => _metrics[endpoint];

  /// Reset all.
  void reset() => _metrics.clear();

  /// Slowest endpoints (sorted descending by avg latency).
  List<EndpointMetrics> get slowest {
    final sorted = List<EndpointMetrics>.of(_metrics.values)
      ..sort((a, b) => b.avgLatencyMs.compareTo(a.avgLatencyMs));
    return sorted;
  }

  /// Endpoints with the lowest success rate.
  List<EndpointMetrics> get mostFailed {
    final sorted = List<EndpointMetrics>.of(_metrics.values)
      ..sort((a, b) => a.successRate.compareTo(b.successRate));
    return sorted;
  }
}

/// Provider for [RequestMetricsCollector].
final requestMetricsProvider = Provider<RequestMetricsCollector>((ref) {
  return RequestMetricsCollector();
});
