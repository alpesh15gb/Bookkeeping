/// Dashboard service — encapsulates all dashboard API calls.
/// Business logic stays here, not in presentation controllers.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';

import '../models/dashboard_models.dart';

class DashboardService {
  DashboardService(this._dio);

  final Dio _dio;

  Future<Result<DashboardKpis>> fetchKpis({String? dateFrom, String? dateTo}) =>
      _get<DashboardKpis>(
        '/dashboard/kpis',
        DashboardKpis.fromJson,
        query: {'date_from': dateFrom, 'date_to': dateTo},
      );

  Future<Result<DashboardMetrics>> fetchMetrics({
    String? dateFrom,
    String? dateTo,
  }) => _get<DashboardMetrics>(
    '/dashboard/metrics',
    DashboardMetrics.fromJson,
    query: {'date_from': dateFrom, 'date_to': dateTo},
  );

  Future<Result<List<TrendPoint>>> fetchRevenueTrend({
    String? dateFrom,
    String? dateTo,
  }) => _getList<TrendPoint>(
    '/dashboard/revenue-trend',
    TrendPoint.fromJson,
    query: {'date_from': dateFrom, 'date_to': dateTo},
  );

  Future<Result<List<TrendPoint>>> fetchExpenseTrend({
    String? dateFrom,
    String? dateTo,
  }) => _getList<TrendPoint>(
    '/dashboard/expense-trend',
    TrendPoint.fromJson,
    query: {'date_from': dateFrom, 'date_to': dateTo},
  );

  /// Combined overdue: shares `GET /dashboard/overdue-alerts` with KPI data.
  Future<Result<OverdueAlertsResponse>> fetchOverdueAlerts() =>
      _get<OverdueAlertsResponse>(
        '/dashboard/overdue-alerts',
        OverdueAlertsResponse.fromJson,
      );

  Future<Result<T>> _get<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (query != null) {
        q.addAll(query);
        q.removeWhere((_, v) => v == null);
      }
      final res = await _dio.get(
        path,
        queryParameters: q.isNotEmpty ? q : null,
      );
      return fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<T>>> _getList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (query != null) {
        q.addAll(query);
        q.removeWhere((_, v) => v == null);
      }
      final res = await _dio.get(
        path,
        queryParameters: q.isNotEmpty ? q : null,
      );
      final list = (res.data as List)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    });
  }
}

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService(ref.watch(apiClientProvider));
});
