/// Riverpod providers for the sync infrastructure.
///
/// These providers wire up [SyncEngine], [SyncScheduler], and the reactive
/// [SyncSummary] stream that the UI reads to show sync status.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_provider.dart';
import '../network/api_client.dart';
import '../network/api_reachability.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';
import 'reference_pull_service.dart';
import 'reference_snapshot_service.dart';
import '../../features/auth/presentation/auth_controller.dart';

// ── Engine ────────────────────────────────────────────────────────────────────

/// The singleton [SyncEngine] instance.
///
/// Consumers that need to register a pusher (e.g. [JournalRepositoryImpl])
/// call `ref.read(syncEngineProvider).registerPusher(...)` during their
/// own provider initialisation.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(databaseProvider);
  final dio = ref.watch(apiClientProvider);
  final engine = SyncEngine(db: db, dio: dio);
  // Register reference-data pull applicators.
  registerReferencePullApplicators(engine, db);
  ref.onDispose(engine.dispose);
  return engine;
});

// ── Active company ID (derived from auth state) ───────────────────────────────

/// Derives the current tenant UUID from the auth controller.
/// Used by the scheduler to scope pull cycles.
final activeCompanyIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.activeMembership?.tenantId;
});

final referenceSnapshotServiceProvider = Provider<ReferenceSnapshotService>((
  ref,
) {
  return ReferenceSnapshotService(
    db: ref.watch(databaseProvider),
    dio: ref.watch(apiClientProvider),
  );
});

final apiReachabilityProvider = Provider<ApiReachabilityService>((ref) {
  final service = ApiReachabilityService(ref.watch(apiClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

// ── Scheduler ─────────────────────────────────────────────────────────────────

/// The singleton [SyncScheduler] instance.
///
/// Call `ref.read(syncSchedulerProvider).start()` from `main()` after
/// `runApp()`.
final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final scheduler = SyncScheduler(
    engine: engine,
    companyIdProvider: () async => ref.read(activeCompanyIdProvider),
    reachabilityProbe: ref.read(apiReachabilityProvider).probe,
    onPull: (engine) async {
      final companyId = ref.read(activeCompanyIdProvider);
      if (companyId != null && companyId.isNotEmpty) {
        await engine.runPullCycle(companyId: companyId);
      }
    },
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

// ── Sync summary ──────────────────────────────────────────────────────────────

/// Real-time [SyncSummary] stream derived from the outbox tables.
///
/// The UI binds to this to show the sync-status indicator (e.g. "3 pending",
/// "Sync failed", "Up to date").
final syncSummaryProvider = StreamProvider<SyncSummary>((ref) {
  final db = ref.watch(databaseProvider);
  final companyId = ref.watch(activeCompanyIdProvider);
  final scopedCompanyId = companyId?.isNotEmpty == true
      ? companyId!
      : '__no_active_company__';
  final operationsQuery = db.select(db.syncOperations)
    ..where((o) => o.companyId.equals(scopedCompanyId));
  final checkpointsQuery = db.select(db.syncCheckpoints)
    ..where((c) => c.companyId.equals(scopedCompanyId));
  final reachability = ref.watch(apiReachabilityProvider);

  var operations = <SyncOperation>[];
  var checkpoints = <SyncCheckpoint>[];
  var isOnline = false;
  var closed = false;
  StreamSubscription<List<SyncOperation>>? operationsSubscription;
  StreamSubscription<List<SyncCheckpoint>>? checkpointsSubscription;
  StreamSubscription<bool>? reachabilitySubscription;

  DateTime? latest(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left.isAfter(right) ? left : right;
  }

  late final StreamController<SyncSummary> controller;
  void emit() {
    if (closed) return;
    DateTime? lastSyncedAt;
    for (final operation in operations) {
      if (operation.status == SyncStatus.synced.name) {
        lastSyncedAt = latest(lastSyncedAt, operation.completedAt);
      }
    }
    for (final checkpoint in checkpoints) {
      lastSyncedAt = latest(lastSyncedAt, checkpoint.updatedAt);
    }

    controller.add(
      SyncSummary(
        pendingCount: operations
            .where(
              (operation) =>
                  operation.status == SyncStatus.pending.name ||
                  operation.status == SyncStatus.syncing.name,
            )
            .length,
        failedCount: operations
            .where((operation) => operation.status == SyncStatus.failed.name)
            .length,
        conflictCount: operations
            .where((operation) => operation.status == SyncStatus.conflict.name)
            .length,
        lastSyncedAt: lastSyncedAt,
        isActive: operations.any(
          (operation) => operation.status == SyncStatus.syncing.name,
        ),
        isOnline: isOnline,
      ),
    );
  }

  controller = StreamController<SyncSummary>(
    onListen: () {
      operationsSubscription = operationsQuery.watch().listen((rows) {
        operations = rows;
        emit();
      }, onError: controller.addError);
      checkpointsSubscription = checkpointsQuery.watch().listen((rows) {
        checkpoints = rows;
        emit();
      }, onError: controller.addError);
      reachabilitySubscription = reachability.changes.listen((reachable) {
        isOnline = reachable;
        emit();
      }, onError: controller.addError);
      unawaited(reachability.probe());
    },
    onCancel: () async {
      closed = true;
      await operationsSubscription?.cancel();
      await checkpointsSubscription?.cancel();
      await reachabilitySubscription?.cancel();
    },
  );

  return controller.stream;
});
