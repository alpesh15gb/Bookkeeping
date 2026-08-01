/// Abstract repository interface for journal entries.
///
/// The UI and notifiers depend only on this interface, never on the
/// implementation.  This allows the repository to be swapped or mocked in
/// tests without touching presentation code.
library;

import '../commands/journal_commands.dart';
import '../entities/journal_entity.dart';

abstract interface class JournalRepository {
  // ── Read ──────────────────────────────────────────────────────────────────

  /// Watch the list of local journal entries, optionally filtered.
  ///
  /// This is a Drift reactive stream — it emits a new list whenever
  /// any row in the underlying table changes.  The UI rebuilds automatically.
  Stream<List<JournalEntryEntity>> watchJournals({JournalFilter? filter});

  /// Read a single journal entry by its stable [localId].
  Future<JournalEntryEntity?> getJournal(String localId);

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Save a new journal draft locally and queue it for sync.
  ///
  /// This operation always succeeds locally (no network required).  The
  /// returned entity has [SyncStatus.pending].
  Future<JournalEntryEntity> saveDraft(CreateJournalCommand command);

  /// Update an existing DRAFT journal and queue the change for sync.
  Future<JournalEntryEntity> updateDraft(UpdateJournalCommand command);

  /// Post a DRAFT journal entry locally.
  ///
  /// Posting is validated locally (balanced, date valid, accounts exist).
  /// The posted status is persisted before a sync operation is queued.
  Future<JournalEntryEntity> postJournal(PostJournalCommand command);

  /// Create a reversal journal entry for a POSTED entry.
  ///
  /// The reversal is a new [JournalEntryEntity] with all directions flipped.
  Future<JournalEntryEntity> reverseJournal(ReverseJournalCommand command);

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Re-queue a [SyncStatus.failed] operation so the engine retries it.
  Future<void> retrySync(String localId);

  /// Resolves a conflict using the deterministic server-wins policy.
  ///
  /// The conflicting local operation is discarded, the conflict record is
  /// removed, and a pull is requested so the local journal reflects the
  /// authoritative remote version.
  Future<void> resolveConflict(String localId);
}
