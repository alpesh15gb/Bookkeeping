/// Domain entity for a journal entry in the offline-first layer.
///
/// This is the type that flows between the [JournalRepository], Riverpod
/// notifiers, and the UI.  It is mapped from [JournalEntry] (Drift row) by
/// [JournalMapper] and is completely independent of Drift generated types.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/sync/journal_lifecycle_status.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/utils/money.dart';
import '../../../accounting/journal/models/direction.dart';

@immutable
class JournalEntryEntity {
  const JournalEntryEntity({
    required this.localId,
    required this.companyId,
    required this.entryDate,
    required this.description,
    required this.lines,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.referenceNumber,
    this.sourceType = 'MANUAL',
    this.syncError,
    this.lastSyncedAt,
    this.localRevision = 0,
  });

  final String localId;
  final String? remoteId;
  final String companyId;
  final String entryDate;
  final String? referenceNumber;
  final String description;
  final String sourceType;
  final JournalLifecycleStatus lifecycleStatus;
  final SyncStatus syncStatus;
  final int localRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt;
  final String? syncError;
  final List<JournalLineEntity> lines;

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get isPosted => lifecycleStatus == JournalLifecycleStatus.posted;
  bool get isDraft => lifecycleStatus == JournalLifecycleStatus.draft;
  bool get isReversed => lifecycleStatus == JournalLifecycleStatus.reversed;
  bool get isSynced => syncStatus == SyncStatus.synced;
  bool get hasSyncIssue => syncStatus.requiresAttention;

  Money get totalDebit => lines
      .where((l) => l.direction.isDebit)
      .fold(const Money.zero(), (s, l) => s + l.amount);

  Money get totalCredit => lines
      .where((l) => l.direction.isCredit)
      .fold(const Money.zero(), (s, l) => s + l.amount);

  Money get difference => (totalDebit - totalCredit).abs();

  bool get isBalanced =>
      lines.length >= 2 &&
      totalDebit.paise > 0 &&
      difference.paise < 1; // less than 1 paise off
}

@immutable
class JournalLineEntity {
  const JournalLineEntity({
    required this.localId,
    required this.journalLocalId,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.direction,
    required this.amount,
    required this.sortOrder,
    this.narration,
  });

  final String localId;
  final String journalLocalId;
  final String accountId;
  final String accountCode;
  final String accountName;
  final Direction direction;
  final Money amount;
  final int sortOrder;
  final String? narration;
}

/// Filter criteria for [JournalRepository.watchJournals].
class JournalFilter {
  const JournalFilter({
    this.search,
    this.lifecycleStatus,
    this.sourceType,
    this.dateFrom,
    this.dateTo,
    this.companyId,
  });

  final String? search;
  final String? lifecycleStatus;
  final String? sourceType;
  final String? dateFrom;
  final String? dateTo;
  final String? companyId;
}
