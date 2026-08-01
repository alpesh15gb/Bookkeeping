/// Sync engine — orchestrates push and pull cycles.
///
/// The engine is the *only* component that touches the remote API.
/// Repositories write to the local database and the outbox; the engine
/// drains the outbox in the background.
///
/// ## Push cycle
/// 1. Read pending [SyncOperation]s from [AppDatabase.syncOperations].
/// 2. For each operation, resolve dependency order.
/// 3. Call the appropriate remote data source.
/// 4. On success: update the entity's [remoteId] and [syncStatus].
/// 5. On retryable failure: apply backoff, increment [attemptCount].
/// 6. On permanent failure: mark as [SyncStatus.failed].
/// 7. On conflict: write a [SyncConflict] row, mark as [SyncStatus.conflict].
///
/// ## Pull cycle
/// 1. Read the [SyncCheckpoints] cursor for `(companyId, '*')`.
/// 2. Call `GET /apexbooks/sync/pull?after=<cursor>`.
/// 3. Apply received events to local tables inside a transaction.
/// 4. Advance the checkpoint only after all events are applied.
///
/// ## Locking
/// A [Mutex] prevents concurrent push cycles for the same session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:mutex/mutex.dart';

import '../database/app_database.dart';
import '../errors/app_exception.dart';
import 'sync_operation.dart';
import 'sync_retry_policy.dart';
import 'sync_status.dart';

/// A function that the sync engine calls to push one operation to the server.
///
/// Implemented per-entity-type and registered via [SyncEngine.registerPusher].
typedef SyncPusher = Future<SyncPushResult> Function(OutboxRecord op);

/// A function that the sync engine calls to apply one pull event locally.
///
/// Returns `true` if the event was handled (known type and successfully
/// applied), `false` if it was skipped (unknown type).  The caller must
/// NOT throw for unknown event types — unknown types are logged and skipped.
typedef PullEventApplicator = Future<bool> Function(Map<String, dynamic> event);

/// Result returned from a [SyncPusher].
class SyncPushResult {
  const SyncPushResult({
    required this.remoteId,
    this.remoteRevision,
    this.referenceNumber,
    this.serverTimestamp,
  });

  /// Server-assigned UUID for the entity.
  final String remoteId;
  final int? remoteRevision;

  /// Server-assigned document number (e.g. `'JNL-0001'`), if returned.
  final String? referenceNumber;
  final DateTime? serverTimestamp;
}

/// Parses the acknowledgement returned by the ApexBooks sync endpoint.
///
/// The production backend uses `acknowledgements`; older deployments used
/// `acknowledged`. Keeping the compatibility handling here prevents each
/// repository from implementing a subtly different sync contract.
SyncPushResult parseSyncPushResponse(
  Object? responseBody,
  Map<String, dynamic> eventPayload, {
  String entityLabel = 'record',
}) {
  if (responseBody is! Map) {
    throw ContractException(
      'Server returned a malformed $entityLabel sync response.',
    );
  }

  final body = responseBody.cast<String, dynamic>();
  final rawAcknowledgements = body['acknowledgements'] ?? body['acknowledged'];
  if (rawAcknowledgements is! List || rawAcknowledgements.isEmpty) {
    throw ContractException(
      'Server $entityLabel sync response is missing acknowledgements.',
    );
  }

  final eventId = eventPayload['event_id']?.toString();
  Map<String, dynamic>? acknowledgement;
  for (final raw in rawAcknowledgements) {
    if (raw is! Map) continue;
    final candidate = raw.cast<String, dynamic>();
    if (eventId == null ||
        candidate['event_id'] == null ||
        candidate['event_id'].toString() == eventId) {
      acknowledgement = candidate;
      break;
    }
  }
  if (acknowledgement == null) {
    throw ContractException(
      'Server acknowledged a different event during $entityLabel sync.',
    );
  }

  final error = acknowledgement['error']?.toString().trim();
  if (error != null && error.isNotEmpty) {
    final normalized = error.toLowerCase();
    if (normalized.contains('conflict') ||
        normalized.contains('immutable') ||
        normalized.contains('already reversed')) {
      throw ConflictException(
        error,
        conflictId: eventPayload['aggregate_id']?.toString(),
      );
    }
    throw PermanentSyncException(
      error,
      statusCode: 422,
      userAction: 'Review the $entityLabel and retry sync.',
    );
  }

  return SyncPushResult(
    remoteId:
        acknowledgement['entity_id']?.toString() ??
        eventPayload['aggregate_id']?.toString() ??
        eventId ??
        '',
    remoteRevision: switch (acknowledgement['revision']) {
      final int value => value,
      final String value => int.tryParse(value),
      _ => null,
    },
    referenceNumber: acknowledgement['reference_number']?.toString(),
    serverTimestamp: DateTime.tryParse(
      acknowledgement['received_at']?.toString() ?? '',
    ),
  );
}

class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required Dio dio,
    SyncRetryPolicy? retryPolicy,
  }) : _db = db,
       _dio = dio,
       _retryPolicy = retryPolicy ?? const SyncRetryPolicy();

  final AppDatabase _db;
  final Dio _dio;
  final SyncRetryPolicy _retryPolicy;
  final _lock = Mutex();

  /// Entity type → pusher function registry.
  final Map<String, SyncPusher> _pushers = {};

  /// Pull cycle lock — shares concurrency rules with the push lock.
  final _pullLock = Mutex();

  /// Registered pull event applicators (eventType → handler).
  final Map<String, PullEventApplicator> _pullApplicators = {};

  bool _disposed = false;

  // ── Registration ──────────────────────────────────────────────────────────

  /// Register a pusher for [entityType] (e.g. `'journal'`, `'invoice'`).
  ///
  /// The pusher is called once per eligible pending operation.
  void registerPusher(String entityType, SyncPusher pusher) {
    _pushers[entityType] = pusher;
  }

  /// Register an applicator for a pull event type (e.g. `'account.created'`).
  void registerPullApplicator(
    String eventType,
    PullEventApplicator applicator,
  ) {
    _pullApplicators[eventType] = applicator;
  }

  // ── Push cycle ────────────────────────────────────────────────────────────

  /// Drains the outbox, pushing pending operations to the server.
  ///
  /// Safe to call concurrently — only one push cycle runs at a time.
  /// Returns the number of operations that were successfully synced.
  Future<int> runPushCycle({String? companyId}) async {
    if (_disposed) return 0;
    if (_lock.isLocked) return 0; // another cycle is already running

    return _lock.protect(() async {
      int synced = 0;
      try {
        // Bound one foreground cycle to 500 operations, but keep reading
        // batches so a normal offline backlog does not take one five-minute
        // timer interval per 50 records.
        for (int batch = 0; batch < 10 && !_disposed; batch++) {
          final driftRows = await _db.pendingOperations(
            limit: 50,
            companyId: companyId,
          );
          if (driftRows.isEmpty) break;

          final ops = driftRows
              .map(
                (r) => OutboxRecord(
                  id: r.id,
                  entityType: r.entityType,
                  entityLocalId: r.entityLocalId,
                  companyId: r.companyId,
                  financialYearId: r.financialYearId,
                  actorId: r.actorId,
                  deviceId: r.deviceId,
                  operationType: r.operationType,
                  payload: r.payload,
                  idempotencyKey: r.idempotencyKey,
                  priority: r.priority,
                  attemptCount: r.attemptCount,
                  status: SyncStatus.values.firstWhere(
                    (s) => s.name == r.status,
                    orElse: () => SyncStatus.localOnly,
                  ),
                  createdAt: r.createdAt,
                  nextAttemptAt: r.nextAttemptAt,
                  startedAt: r.startedAt,
                  completedAt: r.completedAt,
                  lastError: r.lastError,
                  dependencyIds: r.dependencyIds != null
                      ? (jsonDecode(r.dependencyIds!) as List).cast<String>()
                      : null,
                ),
              )
              .toList();

          int batchSynced = 0;
          for (final op in ops) {
            if (_disposed) break;
            if (await _processOperation(op)) {
              synced++;
              batchSynced++;
            }
          }

          if (driftRows.length < 50 || batchSynced == 0) break;
        }
      } catch (error, stackTrace) {
        // Log but never let a cycle-level error propagate.
        // Individual operation errors are recorded per-row.
        developer.log(
          '[push] push cycle error',
          name: 'apexbooks.sync',
          error: error,
          stackTrace: stackTrace,
        );
      }
      try {
        await _db.pruneSyncHistory();
      } catch (error, stackTrace) {
        // Maintenance must not make an otherwise valid sync cycle fail.
        developer.log(
          '[push] sync history cleanup error',
          name: 'apexbooks.sync',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return synced;
    });
  }

  // ── Pull cycle ─────────────────────────────────────────────────────────────

  /// Fetch events from `GET /apexbooks/sync/pull` for [companyId] and apply
  /// them to local reference-data tables.
  ///
  /// Resumes from the last checkpoint for (companyId, entityType).
  /// Advances the checkpoint only inside the same transaction as the event
  /// application. Unknown event types fail the batch so the cursor cannot
  /// advance past data this client version does not understand.
  ///
  /// Returns the number of events applied, or -1 if another pull cycle was
  /// already in flight.
  Future<int> runPullCycle({required String companyId}) async {
    if (_disposed) return 0;
    if (_pullLock.isLocked) return -1;

    return _pullLock.protect(() => _doPullCycle(companyId));
  }

  Future<int> _doPullCycle(String companyId) async {
    int applied = 0;
    const int pageSize = 500;

    try {
      // 1. Read current checkpoint.
      final checkpoint =
          await (_db.select(_db.syncCheckpoints)..where(
                (c) => c.companyId.equals(companyId) & c.entityType.equals('*'),
              ))
              .getSingleOrNull();

      int after = checkpoint?.lastServerSequence ?? 0;

      while (true) {
        // 2. HTTP pull.
        final res = await _dio.get(
          '/apexbooks/sync/pull',
          queryParameters: {'after': after, 'limit': pageSize},
        );
        final body = res.data as Map<String, dynamic>;
        final events = (body['events'] as List?) ?? <dynamic>[];
        final nextCursor = body['next_cursor'] as int? ?? after;

        if (events.isEmpty) break;

        // 3. Apply events inside a transaction.
        int batchApplied = 0;
        await _db.transaction(() async {
          for (final raw in events) {
            final event = raw as Map<String, dynamic>;
            final eventType = event['event_type'] as String?;
            if (eventType == null || eventType.isEmpty) {
              throw const FormatException(
                'Pulled sync event has no event_type.',
              );
            }

            // Verify company scope.
            final eventCompanyId = event['company_id'] as String?;
            if (eventCompanyId != null && eventCompanyId != companyId) {
              throw StateError(
                'Pulled event company does not match the active company.',
              );
            }

            // Dispatch to registered applicator.
            final applicator = _pullApplicators[eventType];
            if (applicator != null) {
              final handled = await applicator(event);
              if (handled) batchApplied++;
            } else {
              // Unknown event type — log and skip.
              throw StateError(
                'This app version cannot apply sync event "$eventType". '
                'The pull checkpoint was not advanced.',
              );
            }
          }

          // 4. Advance checkpoint inside the same transaction.
          await _db
              .into(_db.syncCheckpoints)
              .insertOnConflictUpdate(
                SyncCheckpointsCompanion(
                  companyId: Value(companyId),
                  entityType: const Value('*'),
                  lastServerSequence: Value(nextCursor),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
        });

        applied += batchApplied;

        // 5. If fewer events returned than page size, we've caught up.
        if (events.length < pageSize) break;
        after = nextCursor;
      }
    } catch (e) {
      // If the pull fails completely, the checkpoint is NOT advanced and the
      // cycle will resume from the same position next time.
      developer.log(
        '[pull] pull cycle error',
        name: 'apexbooks.sync',
        error: e,
      );
    }

    return applied;
  }

  /// Processes a single outbox operation.
  ///
  /// Returns `true` if the operation completed successfully.
  Future<bool> _processOperation(OutboxRecord op) async {
    // Check that all declared dependencies are already synced.
    if (op.hasDependencies) {
      final deps = op.dependencyIds!;
      for (final depId in deps) {
        final dep = await (_db.select(
          _db.syncOperations,
        )..where((r) => r.id.equals(depId))).getSingleOrNull();
        if (dep == null) continue; // completed and purged — ok
        if (dep.status != SyncStatus.synced.name) return false; // blocked
      }
    }

    final pusher = _pushers[op.entityType];
    if (pusher == null) {
      // No pusher registered — skip silently (will be picked up later).
      return false;
    }

    // Mark as syncing.
    await _updateOperationStatus(
      op.id,
      status: SyncStatus.syncing,
      startedAt: DateTime.now().toUtc(),
    );

    try {
      final result = await pusher(op);

      // --- Success ---
      await _db.transaction(() async {
        // Mark outbox entry as synced.
        await _updateOperationStatus(
          op.id,
          status: SyncStatus.synced,
          completedAt: DateTime.now().toUtc(),
        );

        // Update the entity's sync metadata.
        await _applyPushSuccess(op, result);
      });

      return true;
    } on ConflictException catch (e) {
      await _handleConflict(op, e);
      return false;
    } catch (e) {
      await _handleFailure(op, e);
      return false;
    }
  }

  // ── Success handling ──────────────────────────────────────────────────────

  Future<void> _applyPushSuccess(OutboxRecord op, SyncPushResult result) async {
    final now = DateTime.now().toUtc();
    switch (op.entityType) {
      case 'journal':
        await (_db.update(
          _db.journalEntries,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          JournalEntriesCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
            referenceNumber: result.referenceNumber != null
                ? Value(result.referenceNumber!)
                : const Value.absent(),
          ),
        );
      case 'invoice':
        await (_db.update(
          _db.invoices,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          InvoicesCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'payment':
        await (_db.update(
          _db.payments,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PaymentsCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'inventory':
        await (_db.update(
          _db.inventoryMovements,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          InventoryMovementsCompanion(
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'stock_item':
        await (_db.update(
          _db.stockItems,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          StockItemsCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            updatedAt: Value(now),
          ),
        );
      case 'purchase_order':
        await (_db.update(
          _db.purchaseOrders,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseOrdersCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'purchase_receipt':
        await (_db.update(
          _db.purchaseReceipts,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseReceiptsCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'purchase_invoice':
        await (_db.update(
          _db.purchaseInvoices,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseInvoicesCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'sales_delivery':
        await (_db.update(
          _db.salesDeliveries,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          SalesDeliveriesCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'sales_return':
        await (_db.update(
          _db.salesReturns,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          SalesReturnsCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'purchase_return':
        await (_db.update(
          _db.purchaseReturns,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseReturnsCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'credit_note':
        await (_db.update(
          _db.creditNotes,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          CreditNotesCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'debit_note':
        await (_db.update(
          _db.debitNotes,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          DebitNotesCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            lastSyncedAt: Value(now),
            syncError: const Value(null),
          ),
        );
      case 'bank_statement':
        await (_db.update(
          _db.bankStatements,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          BankStatementsCompanion(
            remoteId: Value(result.remoteId),
            syncStatus: Value(SyncStatus.synced.name),
          ),
        );
      case 'reconciliation':
        await (_db.update(
          _db.bankReconciliations,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          BankReconciliationsCompanion(
            syncStatus: Value(SyncStatus.synced.name),
          ),
        );
    }
  }

  // ── Conflict handling ─────────────────────────────────────────────────────

  Future<void> _handleConflict(OutboxRecord op, ConflictException e) async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      // Record the conflict for user resolution.
      await _db
          .into(_db.syncConflicts)
          .insertOnConflictUpdate(
            SyncConflictsCompanion(
              id: Value(e.conflictId ?? op.id),
              entityType: Value(op.entityType),
              entityLocalId: Value(op.entityLocalId),
              localPayload: Value(op.payload),
              remotePayload: Value(e.message),
              detectedAt: Value(now),
            ),
          );

      // Mark the outbox entry as conflicted.
      await _updateOperationStatus(op.id, status: SyncStatus.conflict);

      // Mark the entity as conflicted.
      await _markEntityStatus(op, SyncStatus.conflict, error: e.message);
    });
  }

  // ── Failure handling ──────────────────────────────────────────────────────

  Future<void> _handleFailure(OutboxRecord op, Object e) async {
    final decision = _retryPolicy.decide(e, attemptCount: op.attemptCount);
    final newAttemptCount = op.attemptCount + 1;

    int? retryAfter;
    if (e is RetryableSyncException) retryAfter = e.retryAfterSeconds;

    final nextAttempt = decision == RetryDecision.retry
        ? _retryPolicy.nextAttemptAt(
            newAttemptCount,
            retryAfterSeconds: retryAfter,
          )
        : null;

    final status = decision == RetryDecision.retry
        ? SyncStatus
              .pending // reset to pending so it's re-queried
        : SyncStatus.failed;

    await _db.transaction(() async {
      await (_db.update(
        _db.syncOperations,
      )..where((r) => r.id.equals(op.id))).write(
        SyncOperationsCompanion(
          status: Value(status.name),
          attemptCount: Value(newAttemptCount),
          nextAttemptAt: Value(nextAttempt),
          lastError: Value(e.toString()),
        ),
      );

      if (decision == RetryDecision.permanent) {
        await _markEntityStatus(op, SyncStatus.failed, error: e.toString());
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _updateOperationStatus(
    String id, {
    required SyncStatus status,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    await (_db.update(_db.syncOperations)..where((r) => r.id.equals(id))).write(
      SyncOperationsCompanion(
        status: Value(status.name),
        startedAt: startedAt != null ? Value(startedAt) : const Value.absent(),
        completedAt: completedAt != null
            ? Value(completedAt)
            : const Value.absent(),
      ),
    );
  }

  Future<void> _markEntityStatus(
    OutboxRecord op,
    SyncStatus status, {
    String? error,
  }) async {
    switch (op.entityType) {
      case 'journal':
        await (_db.update(
          _db.journalEntries,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          JournalEntriesCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'invoice':
        await (_db.update(
          _db.invoices,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          InvoicesCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'payment':
        await (_db.update(
          _db.payments,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PaymentsCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'inventory':
        await (_db.update(
          _db.inventoryMovements,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          InventoryMovementsCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'stock_item':
        await (_db.update(_db.stockItems)
              ..where((r) => r.localId.equals(op.entityLocalId)))
            .write(StockItemsCompanion(syncStatus: Value(status.name)));
      case 'purchase_order':
        await (_db.update(
          _db.purchaseOrders,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseOrdersCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'purchase_receipt':
        await (_db.update(
          _db.purchaseReceipts,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseReceiptsCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'purchase_invoice':
        await (_db.update(
          _db.purchaseInvoices,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseInvoicesCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'sales_delivery':
        await (_db.update(
          _db.salesDeliveries,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          SalesDeliveriesCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'sales_return':
        await (_db.update(
          _db.salesReturns,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          SalesReturnsCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'purchase_return':
        await (_db.update(
          _db.purchaseReturns,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          PurchaseReturnsCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'credit_note':
        await (_db.update(
          _db.creditNotes,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          CreditNotesCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'debit_note':
        await (_db.update(
          _db.debitNotes,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          DebitNotesCompanion(
            syncStatus: Value(status.name),
            syncError: Value(error),
          ),
        );
      case 'bank_statement':
        await (_db.update(_db.bankStatements)
              ..where((r) => r.localId.equals(op.entityLocalId)))
            .write(BankStatementsCompanion(syncStatus: Value(status.name)));
      case 'reconciliation':
        await (_db.update(
          _db.bankReconciliations,
        )..where((r) => r.localId.equals(op.entityLocalId))).write(
          BankReconciliationsCompanion(syncStatus: Value(status.name)),
        );
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
  }
}
