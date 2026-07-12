/// Dashboard controller — orchestrates concurrent API calls with error isolation.
/// Each data slice loads independently so one failure never blanks the whole view.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/dashboard_models.dart';
import '../services/dashboard_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Each dashboard widget gets its own loading/success/failure state so errors
/// are isolated and partial loading is visible.
class DashboardState {
  const DashboardState({
    this.kpis = const AsyncLoading(),
    this.metrics = const AsyncLoading(),
    this.revenueTrend = const AsyncLoading(),
    this.expenseTrend = const AsyncLoading(),
    this.overdueAlerts = const AsyncLoading(),
    this.refreshing = false,
  });

  final AsyncValue<DashboardKpis> kpis;
  final AsyncValue<DashboardMetrics> metrics;
  final AsyncValue<List<TrendPoint>> revenueTrend;
  final AsyncValue<List<TrendPoint>> expenseTrend;
  final AsyncValue<OverdueAlertsResponse> overdueAlerts;

  /// True while a manual pull-to-refresh is in progress.
  final bool refreshing;

  DashboardState copyWith({
    AsyncValue<DashboardKpis>? kpis,
    AsyncValue<DashboardMetrics>? metrics,
    AsyncValue<List<TrendPoint>>? revenueTrend,
    AsyncValue<List<TrendPoint>>? expenseTrend,
    AsyncValue<OverdueAlertsResponse>? overdueAlerts,
    bool? refreshing,
  }) => DashboardState(
    kpis: kpis ?? this.kpis,
    metrics: metrics ?? this.metrics,
    revenueTrend: revenueTrend ?? this.revenueTrend,
    expenseTrend: expenseTrend ?? this.expenseTrend,
    overdueAlerts: overdueAlerts ?? this.overdueAlerts,
    refreshing: refreshing ?? this.refreshing,
  );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier(this._service) : super(const DashboardState());

  final DashboardService _service;

  /// Fires all 5 requests concurrently. Each updates independently.
  Future<void> load() async {
    state = state.copyWith(
      kpis: const AsyncLoading(),
      metrics: const AsyncLoading(),
      revenueTrend: const AsyncLoading(),
      expenseTrend: const AsyncLoading(),
      overdueAlerts: const AsyncLoading(),
    );

    // Fire all in parallel — error isolation built in.
    await Future.wait([
      _loadKpis(),
      _loadMetrics(),
      _loadRevenueTrend(),
      _loadExpenseTrend(),
      _loadOverdueAlerts(),
    ]);
  }

  /// Pull-to-refresh — keeps current data visible while reloading.
  Future<void> refresh() async {
    state = state.copyWith(refreshing: true);
    await Future.wait([
      _loadKpis(),
      _loadMetrics(),
      _loadRevenueTrend(),
      _loadExpenseTrend(),
      _loadOverdueAlerts(),
    ]);
    state = state.copyWith(refreshing: false);
  }

  Future<void> _loadKpis() async {
    final result = await _service.fetchKpis();
    state = state.copyWith(
      kpis: switch (result) {
        Success(:final value) => AsyncData(value),
        Failure(:final error) => AsyncError(error, StackTrace.current),
        _ => state.kpis,
      },
    );
  }

  Future<void> _loadMetrics() async {
    final result = await _service.fetchMetrics();
    state = state.copyWith(
      metrics: switch (result) {
        Success(:final value) => AsyncData(value),
        Failure(:final error) => AsyncError(error, StackTrace.current),
        _ => state.metrics,
      },
    );
  }

  Future<void> _loadRevenueTrend() async {
    final result = await _service.fetchRevenueTrend();
    state = state.copyWith(
      revenueTrend: switch (result) {
        Success(:final value) => AsyncData(value),
        Failure(:final error) => AsyncError(error, StackTrace.current),
        _ => state.revenueTrend,
      },
    );
  }

  Future<void> _loadExpenseTrend() async {
    final result = await _service.fetchExpenseTrend();
    state = state.copyWith(
      expenseTrend: switch (result) {
        Success(:final value) => AsyncData(value),
        Failure(:final error) => AsyncError(error, StackTrace.current),
        _ => state.expenseTrend,
      },
    );
  }

  Future<void> _loadOverdueAlerts() async {
    final result = await _service.fetchOverdueAlerts();
    state = state.copyWith(
      overdueAlerts: switch (result) {
        Success(:final value) => AsyncData(value),
        Failure(:final error) => AsyncError(error, StackTrace.current),
        _ => state.overdueAlerts,
      },
    );
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
      return DashboardNotifier(ref.watch(dashboardServiceProvider));
    });
