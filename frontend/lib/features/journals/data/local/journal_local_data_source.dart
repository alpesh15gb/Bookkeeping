/// Local data source for journal entries.
///
/// This is the only file that talks to Drift directly for journals.
/// All SQL queries live here; repositories compose them into transactions.
library;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class JournalLocalDataSource {
  const JournalLocalDataSource(this._db);
  final AppDatabase _db;

  // ── Journal entry header ──────────────────────────────────────────────────

  Future<void> upsertJournal(JournalEntriesCompanion companion) async {
    await _db.into(_db.journalEntries).insertOnConflictUpdate(companion);
  }

  Future<JournalEntry?> getJournal(String localId) {
    return (_db.select(_db.journalEntries)
          ..where((r) => r.localId.equals(localId) & r.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Watch all non-deleted journals for [companyId], optionally filtered.
  Stream<List<JournalEntry>> watchJournals({
    required String companyId,
    String? search,
    String? status,
    String? sourceType,
    String? dateFrom,
    String? dateTo,
  }) {
    final query = _db.select(_db.journalEntries)
      ..where((r) {
        Expression<bool> where =
            r.companyId.equals(companyId) & r.deletedAt.isNull();
        if (status != null) where = where & r.lifecycleStatus.equals(status);
        if (sourceType != null) {
          where = where & r.sourceType.equals(sourceType);
        }
        if (dateFrom != null) {
          where = where & r.entryDate.isBiggerOrEqualValue(dateFrom);
        }
        if (dateTo != null) {
          where = where & r.entryDate.isSmallerOrEqualValue(dateTo);
        }
        return where;
      })
      ..orderBy([
        (r) => OrderingTerm.desc(r.entryDate),
        (r) => OrderingTerm.desc(r.createdAt),
      ]);

    if (search != null && search.isNotEmpty) {
      // Client-side text filter — acceptable for typical journal volumes.
      return query.watch().map(
        (rows) => rows
            .where(
              (r) =>
                  r.description.toLowerCase().contains(search.toLowerCase()) ||
                  (r.referenceNumber ?? '').toLowerCase().contains(
                    search.toLowerCase(),
                  ),
            )
            .toList(),
      );
    }
    return query.watch();
  }

  // ── Journal lines ─────────────────────────────────────────────────────────

  Future<void> upsertLines(List<JournalLinesCompanion> companions) async {
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.journalLines, companions);
    });
  }

  Future<List<JournalLine>> getLinesForJournal(String journalLocalId) {
    return (_db.select(_db.journalLines)
          ..where((r) => r.journalLocalId.equals(journalLocalId))
          ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
        .get();
  }

  Stream<List<JournalLine>> watchLinesForJournal(String journalLocalId) {
    return (_db.select(_db.journalLines)
          ..where((r) => r.journalLocalId.equals(journalLocalId))
          ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
        .watch();
  }

  // ── Sync state helpers ────────────────────────────────────────────────────

  Future<void> updateSyncStatus(
    String localId, {
    required String syncStatus,
    String? remoteId,
    String? referenceNumber,
    String? syncError,
    DateTime? lastSyncedAt,
    bool? isDirty,
  }) async {
    await (_db.update(
      _db.journalEntries,
    )..where((r) => r.localId.equals(localId))).write(
      JournalEntriesCompanion(
        syncStatus: Value(syncStatus),
        remoteId: remoteId != null ? Value(remoteId) : const Value.absent(),
        referenceNumber: referenceNumber != null
            ? Value(referenceNumber)
            : const Value.absent(),
        syncError: syncError != null ? Value(syncError) : const Value(null),
        lastSyncedAt: lastSyncedAt != null
            ? Value(lastSyncedAt)
            : const Value.absent(),
        isDirty: isDirty != null ? Value(isDirty) : const Value.absent(),
      ),
    );
  }
}
