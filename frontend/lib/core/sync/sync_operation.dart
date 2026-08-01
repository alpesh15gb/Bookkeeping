/// Domain model for a pending sync operation read from the outbox.
///
/// Distinguishable from the Drift-generated [SyncOperation] row type
/// (from the `sync_operations` table in [AppDatabase]).  This domain
/// model carries [SyncStatus] as a typed enum rather than a raw string,
/// and exposes the execution context needed for scoped sync processing.
library;

import 'sync_status.dart';

/// A single pending outbox entry waiting to be pushed to the server.
class OutboxRecord {
  const OutboxRecord({
    required this.id,
    required this.entityType,
    required this.entityLocalId,
    required this.companyId,
    required this.actorId,
    required this.deviceId,
    required this.operationType,
    required this.payload,
    required this.idempotencyKey,
    required this.priority,
    required this.attemptCount,
    required this.status,
    required this.createdAt,
    this.financialYearId,
    this.nextAttemptAt,
    this.startedAt,
    this.completedAt,
    this.lastError,
    this.dependencyIds,
  });

  final String id;
  final String entityType;
  final String entityLocalId;

  // ── Execution context (stored at queue time, never inferred from UI) ──────────

  /// Tenant / company UUID.
  final String companyId;

  /// Financial-year UUID.  Non-null for FY-dependent operations
  /// (journal.posted, invoice.posted).  Null for reference-data pushes.
  final String? financialYearId;

  /// User UUID who queued this operation.
  final String actorId;

  /// Device UUID that created this operation.
  final String deviceId;

  // ── Operation payload ─────────────────────────────────────────────────────────

  final String operationType;
  final String payload; // raw JSON
  final String idempotencyKey;
  final int priority;
  final int attemptCount;
  final SyncStatus status;
  final DateTime createdAt;
  final DateTime? nextAttemptAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? lastError;

  /// IDs of [OutboxRecord.id] values that must complete before this op runs.
  final List<String>? dependencyIds;

  bool get hasDependencies =>
      dependencyIds != null && dependencyIds!.isNotEmpty;
}

/// A conflict between local and remote versions of an entity.
///
/// Stored in the `sync_conflicts` table and surfaced for user resolution
/// in the Sync Centre.
class ConflictRecord {
  const ConflictRecord({
    required this.id,
    required this.entityType,
    required this.entityLocalId,
    required this.localPayload,
    required this.remotePayload,
    required this.detectedAt,
    this.resolution,
    this.resolvedAt,
  });

  final String id;
  final String entityType;
  final String entityLocalId;
  final String localPayload;
  final String remotePayload;
  final DateTime detectedAt;
  final String? resolution;
  final DateTime? resolvedAt;

  bool get isResolved => resolution != null;
}
