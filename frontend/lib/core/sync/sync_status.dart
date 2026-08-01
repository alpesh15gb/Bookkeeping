/// Sync status model for offline-first entities.
///
/// Describes the **delivery** state — has the record been sent to and
/// acknowledged by the server?  This is independent of the entity's own
/// lifecycle status ([JournalLifecycleStatus]), which describes the domain
/// state (draft / posted / reversed).
///
/// Every synchronisable entity row carries a [SyncStatus] that the UI can
/// display.  Business behaviour is driven by the repository and sync engine,
/// not by the UI inspecting this value.
library;

/// The synchronisation (delivery) state of a single local entity or outbox
/// operation.
enum SyncStatus {
  /// Record was created locally and has never been queued for a remote push.
  localOnly,

  /// A push operation is queued in the outbox, waiting to be sent.
  /// Covers creates, updates, and deletes — the operation type is encoded
  /// in the outbox row itself.
  pending,

  /// The outbox operation is currently being sent to the server.
  syncing,

  /// The last push was acknowledged successfully by the server.
  synced,

  /// The last push failed with a non-retryable error.
  ///
  /// The entity remains usable locally; user action is required before
  /// the sync engine will retry.
  failed,

  /// The server and local entity both changed since the last successful sync.
  ///
  /// A [ConflictRecord] row has been created; the user must resolve it.
  conflict;

  /// Returns true while a push to the server is pending or active.
  bool get isPending => this == pending;

  /// Returns true if the entity has been confirmed by the server.
  bool get isSynced => this == synced;

  /// Returns true when user attention is required.
  bool get requiresAttention => this == failed || this == conflict;

  /// Short display label for sync-status badges.
  String get label => switch (this) {
    localOnly => 'Local',
    pending => 'Pending',
    syncing => 'Syncing',
    synced => 'Synced',
    failed => 'Sync failed',
    conflict => 'Conflict',
  };
}

/// A high-level summary of the sync system state, shown in the sync centre.
class SyncSummary {
  const SyncSummary({
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
    required this.lastSyncedAt,
    required this.isActive,
    required this.isOnline,
  });

  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final DateTime? lastSyncedAt;

  /// True while the sync engine is actively sending or receiving.
  final bool isActive;

  /// True if the last connectivity probe was reachable.
  final bool isOnline;

  bool get hasWork => pendingCount > 0;
  bool get hasIssues => failedCount > 0 || conflictCount > 0;

  String get statusLabel {
    if (isActive) return 'Syncing…';
    if (!isOnline) return 'Offline';
    if (conflictCount > 0) return 'Conflict requires attention';
    if (failedCount > 0) return 'Sync failed';
    if (pendingCount > 0) {
      return '$pendingCount change${pendingCount == 1 ? '' : 's'} pending';
    }
    if (lastSyncedAt != null) return 'Up to date';
    return 'Not yet synced';
  }

  SyncSummary copyWith({
    int? pendingCount,
    int? failedCount,
    int? conflictCount,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    bool? isActive,
    bool? isOnline,
  }) => SyncSummary(
    pendingCount: pendingCount ?? this.pendingCount,
    failedCount: failedCount ?? this.failedCount,
    conflictCount: conflictCount ?? this.conflictCount,
    lastSyncedAt: clearLastSyncedAt
        ? null
        : (lastSyncedAt ?? this.lastSyncedAt),
    isActive: isActive ?? this.isActive,
    isOnline: isOnline ?? this.isOnline,
  );
}
