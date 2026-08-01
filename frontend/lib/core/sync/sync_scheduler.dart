/// Sync scheduler — triggers push/pull cycles based on app lifecycle events,
/// connectivity changes, and a periodic timer.
///
/// The scheduler observes:
/// - App lifecycle (resume → immediate push + pull).
/// - Connectivity state changes → push when going online.
/// - A periodic timer (every 5 minutes while foregrounded).
/// - Manual trigger from the UI (Sync Centre "Sync now" button).
///
/// The scheduler does NOT guarantee background execution on any platform.
/// For foreground-only use (Windows, first-launch Android/iOS), this is
/// sufficient.  Background execution can be layered on top later without
/// changing the sync engine or data model.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

class SyncScheduler with WidgetsBindingObserver {
  SyncScheduler({
    required SyncEngine engine,
    Duration interval = const Duration(minutes: 5),
    Future<void> Function(SyncEngine engine)? onPull,
    Future<String?> Function()? companyIdProvider,
    Future<bool> Function()? reachabilityProbe,
  }) : _engine = engine,
       _interval = interval,
       _onPull = onPull,
       _companyIdProvider = companyIdProvider,
       _reachabilityProbe = reachabilityProbe;

  final SyncEngine _engine;
  final Duration _interval;
  final Future<void> Function(SyncEngine engine)? _onPull;
  final Future<String?> Function()? _companyIdProvider;
  final Future<bool> Function()? _reachabilityProbe;

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _disposed = false;

  /// Start observing lifecycle and connectivity events.
  ///
  /// Call this once from `main()` after the app is running.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _startConnectivityWatcher();

    // Kick off an initial cycle immediately.
    _trigger('start');
  }

  /// Force an immediate push cycle.  Safe to call from the UI ("Sync now").
  Future<void> syncNow() => _trigger('manual');

  // ── WidgetsBindingObserver ────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trigger('resume');
    }
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _trigger('timer'));
  }

  // ── Connectivity ──────────────────────────────────────────────────────────

  void _startConnectivityWatcher() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) _trigger('connectivity');
    });
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _trigger(String reason) async {
    if (_disposed) return;
    final companyId = await _companyIdProvider?.call();
    if (_companyIdProvider != null &&
        (companyId == null || companyId.isEmpty)) {
      return;
    }
    if (_reachabilityProbe != null && !await _reachabilityProbe()) return;
    try {
      await _engine.runPushCycle(companyId: companyId);
    } catch (_) {
      // The engine is responsible for per-operation error recording.
    }
    try {
      if (_onPull != null) await _onPull(_engine);
    } catch (_) {
      // Pull cycle errors are recorded per-batch and do not break the app.
    }
  }

  // ── Disposal ──────────────────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connectivitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _engine.dispose();
  }
}
