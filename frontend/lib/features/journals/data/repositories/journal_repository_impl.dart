/// Implementation of [JournalRepository].
///
/// This is the central coordinator for all journal operations.  Every write:
/// 1. Validates the command.
/// 2. Writes to local SQLite inside a transaction.
/// 3. Inserts a [SyncOperation] in the same transaction (outbox).
/// 4. Returns the local result immediately (no network required).
///
/// The [SyncEngine] drains the outbox asynchronously.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/ids/id_generator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/utils/money.dart';
import '../../../accounting/journal/models/direction.dart';
import '../../../accounting/journal/models/journal_line.dart' as form_models;
import '../local/journal_local_data_source.dart';
import '../mappers/journal_mapper.dart';
import '../remote/journal_remote_data_source.dart';
import '../../domain/commands/journal_commands.dart';
import '../../domain/entities/journal_entity.dart';
import '../../domain/repositories/journal_repository.dart';

class JournalRepositoryImpl implements JournalRepository {
  JournalRepositoryImpl({
    required AppDatabase db,
    required JournalLocalDataSource localDs,
    required SyncEngine syncEngine,
    required Dio dio,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() companyIdProvider,
    required Future<String> Function() actorIdProvider,
  }) : _db = db,
       _localDs = localDs,
       _syncEngine = syncEngine,
       _dio = dio,
       _deviceIdProvider = deviceIdProvider,
       _companyIdProvider = companyIdProvider,
       _actorIdProvider = actorIdProvider {
    // Register the pusher for this entity type once.
    _syncEngine.registerPusher('journal', (op) => journalPusher(op, _dio));
  }

  final AppDatabase _db;
  final JournalLocalDataSource _localDs;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  // ── Read ──────────────────────────────────────────────────────────────────

  @override
  Stream<List<JournalEntryEntity>> watchJournals({
    JournalFilter? filter,
  }) async* {
    final companyId = filter?.companyId ?? await _companyIdProvider();
    // Re-emit whenever the journal headers change.
    await for (final headers in _localDs.watchJournals(
      companyId: companyId,
      search: filter?.search,
      status: filter?.lifecycleStatus,
      sourceType: filter?.sourceType,
      dateFrom: filter?.dateFrom,
      dateTo: filter?.dateTo,
    )) {
      final List<JournalEntryEntity> result = [];
      for (final header in headers) {
        final lines = await _localDs.getLinesForJournal(header.localId);
        result.add(JournalMapper.toDomain(header, lines));
      }
      yield result;
    }
  }

  @override
  Future<JournalEntryEntity?> getJournal(String localId) async {
    final header = await _localDs.getJournal(localId);
    if (header == null) return null;
    final lines = await _localDs.getLinesForJournal(localId);
    return JournalMapper.toDomain(header, lines);
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  @override
  Future<JournalEntryEntity> saveDraft(CreateJournalCommand cmd) async {
    _validateDraftCommand(cmd);

    final localId = IdGenerator.newId();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final now = DateTime.now().toUtc();
    final payload = JournalMapper.toCreatePayloadJson(
      cmd,
      localId,
      deviceId,
      now,
      companyId,
      eventType: 'journal.created',
    );

    await _db.transaction(() async {
      // 1. Insert journal header.
      await _localDs.upsertJournal(
        JournalEntriesCompanion(
          localId: Value(localId),
          companyId: Value(companyId),
          entryDate: Value(cmd.entryDate),
          referenceNumber: Value(
            cmd.referenceNumber.isNotEmpty ? cmd.referenceNumber : null,
          ),
          description: Value(cmd.description),
          lifecycleStatus: const Value('draft'),
          syncStatus: Value(SyncStatus.pending.name),
          isDirty: const Value(true),
          originDeviceId: Value(deviceId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // 2. Insert journal lines.
      final lineCompanions = <JournalLinesCompanion>[];
      for (int i = 0; i < cmd.lines.length; i++) {
        final line = cmd.lines[i];
        final money = Money.fromRupees(line.amount);
        lineCompanions.add(
          JournalLinesCompanion(
            localId: Value(IdGenerator.newId()),
            journalLocalId: Value(localId),
            accountId: Value(line.accountId),
            accountCode: Value(line.accountCode),
            accountName: Value(line.accountName),
            direction: Value(line.direction.value),
            amountPaise: Value(money.toPaise()),
            narration: Value(line.narration),
            sortOrder: Value(i),
          ),
        );
      }
      await _localDs.upsertLines(lineCompanions);
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(IdGenerator.createKey('journal', localId)),
              entityType: const Value('journal'),
              entityLocalId: Value(localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              financialYearId: const Value(null),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(IdGenerator.createKey('journal', localId)),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    final entity = await getJournal(localId);
    return entity!;
  }

  @override
  Future<JournalEntryEntity> updateDraft(UpdateJournalCommand cmd) async {
    _validateDraftCommand(
      CreateJournalCommand(
        companyId: cmd.companyId,
        entryDate: cmd.entryDate,
        referenceNumber: cmd.referenceNumber,
        description: cmd.description,
        lines: cmd.lines,
      ),
    );

    final existing = await _localDs.getJournal(cmd.localId);
    if (existing == null) {
      throw ValidationException('Journal entry not found: ${cmd.localId}');
    }
    if (existing.lifecycleStatus != 'draft') {
      throw const ValidationException(
        'Posted journals are immutable; use reversal for corrections.',
      );
    }

    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final now = DateTime.now().toUtc();
    final nextRevision = existing.localRevision + 1;
    final payload = JournalMapper.toUpdatePayloadJson(
      cmd,
      deviceId: deviceId,
      actorId: actorId,
      occurredAt: now,
      eventId: IdGenerator.newId(),
    );

    await _db.transaction(() async {
      await (_db.update(
        _db.journalEntries,
      )..where((row) => row.localId.equals(cmd.localId))).write(
        JournalEntriesCompanion(
          companyId: Value(companyId),
          entryDate: Value(cmd.entryDate),
          referenceNumber: Value(
            cmd.referenceNumber.isEmpty ? null : cmd.referenceNumber,
          ),
          description: Value(cmd.description),
          localRevision: Value(nextRevision),
          updatedAt: Value(now),
          syncStatus: Value(SyncStatus.pending.name),
          isDirty: const Value(true),
          syncError: const Value(null),
        ),
      );
      await (_db.delete(
        _db.journalLines,
      )..where((row) => row.journalLocalId.equals(cmd.localId))).go();
      await _localDs.upsertLines([
        for (var i = 0; i < cmd.lines.length; i++)
          JournalLinesCompanion(
            localId: Value(IdGenerator.newId()),
            journalLocalId: Value(cmd.localId),
            accountId: Value(cmd.lines[i].accountId),
            accountCode: Value(cmd.lines[i].accountCode),
            accountName: Value(cmd.lines[i].accountName),
            direction: Value(cmd.lines[i].direction.value),
            amountPaise: Value(Money.fromRupees(cmd.lines[i].amount).toPaise()),
            narration: Value(cmd.lines[i].narration),
            sortOrder: Value(i),
          ),
      ]);
      await _db
          .into(_db.syncOperations)
          .insertOnConflictUpdate(
            SyncOperationsCompanion(
              id: Value(
                IdGenerator.updateKey('journal', cmd.localId, nextRevision),
              ),
              entityType: const Value('journal'),
              entityLocalId: Value(cmd.localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              financialYearId: const Value(null),
              operationType: const Value('update'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.updateKey('journal', cmd.localId, nextRevision),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await getJournal(cmd.localId))!;
  }

  @override
  Future<JournalEntryEntity> postJournal(PostJournalCommand cmd) async {
    final header = await _localDs.getJournal(cmd.localId);
    if (header == null) {
      throw ValidationException('Journal entry not found: ${cmd.localId}');
    }
    if (header.lifecycleStatus == 'posted') {
      throw const ValidationException('Journal entry is already posted.');
    }

    final lines = await _localDs.getLinesForJournal(cmd.localId);
    final entity = JournalMapper.toDomain(header, lines);

    if (!entity.isBalanced) {
      throw const ValidationException(
        'Journal is out of balance. Debit and credit totals must match.',
      );
    }

    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final now = DateTime.now().toUtc();
    final payloadJson = JournalMapper.toCreatePayloadJson(
      CreateJournalCommand(
        companyId: companyId,
        entryDate: header.entryDate,
        referenceNumber: header.referenceNumber ?? '',
        description: header.description,
        lines: lines
            .map(
              (line) => form_models.JournalLine(
                id: line.localId,
                accountId: line.accountId,
                accountName: line.accountName,
                accountCode: line.accountCode,
                amount: Money.fromPaise(line.amountPaise).toRupees(),
                direction: Direction.fromString(line.direction),
                narration: line.narration,
              ),
            )
            .toList(),
      ),
      cmd.localId,
      deviceId,
      now,
      companyId,
      eventId: IdGenerator.newId(),
      eventType: 'journal.posted',
    );

    await _db.transaction(() async {
      await (_db.update(
        _db.journalEntries,
      )..where((r) => r.localId.equals(cmd.localId))).write(
        JournalEntriesCompanion(
          lifecycleStatus: const Value('posted'),
          syncStatus: Value(SyncStatus.pending.name),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      );
      await _db
          .into(_db.syncOperations)
          .insertOnConflictUpdate(
            SyncOperationsCompanion(
              id: Value(IdGenerator.actionKey('journal', 'post', cmd.localId)),
              entityType: const Value('journal'),
              entityLocalId: Value(cmd.localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              financialYearId: const Value(null),
              operationType: const Value('post'),
              payload: Value(payloadJson),
              idempotencyKey: Value(
                IdGenerator.actionKey('journal', 'post', cmd.localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await getJournal(cmd.localId))!;
  }

  @override
  Future<JournalEntryEntity> reverseJournal(ReverseJournalCommand cmd) async {
    final header = await _localDs.getJournal(cmd.localId);
    if (header == null) {
      throw ValidationException('Journal entry not found: ${cmd.localId}');
    }
    if (header.lifecycleStatus != 'posted') {
      throw const ValidationException('Only POSTED journals can be reversed.');
    }

    final originalLines = await _localDs.getLinesForJournal(cmd.localId);

    // Build a reversal CreateJournalCommand with all directions flipped.
    final reversalLines = originalLines.map((l) {
      final reversed = l.direction == 'DEBIT' ? 'CREDIT' : 'DEBIT';
      return _ReversalLine(
        accountId: l.accountId,
        accountCode: l.accountCode,
        accountName: l.accountName,
        direction: reversed,
        amountPaise: l.amountPaise,
        narration: l.narration,
      );
    }).toList();

    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final now = DateTime.now().toUtc();
    final reversalId = IdGenerator.newId();

    await _db.transaction(() async {
      // The original becomes an immutable reversed record.  The compensating
      // entry below remains a separate posted journal for audit/reporting.
      await (_db.update(
        _db.journalEntries,
      )..where((r) => r.localId.equals(cmd.localId))).write(
        JournalEntriesCompanion(
          lifecycleStatus: const Value('reversed'),
          updatedAt: Value(now),
        ),
      );

      // Insert reversal journal header.
      await _localDs.upsertJournal(
        JournalEntriesCompanion(
          localId: Value(reversalId),
          companyId: Value(companyId),
          entryDate: Value(cmd.reversalDate),
          description: Value(
            cmd.description.isNotEmpty
                ? cmd.description
                : 'Reversal of ${header.description}',
          ),
          sourceType: const Value('JOURNAL_REVERSAL'),
          lifecycleStatus: const Value('posted'),
          syncStatus: Value(SyncStatus.pending.name),
          isDirty: const Value(true),
          originDeviceId: Value(deviceId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Insert reversed lines.
      final companions = <JournalLinesCompanion>[];
      for (int i = 0; i < reversalLines.length; i++) {
        final l = reversalLines[i];
        companions.add(
          JournalLinesCompanion(
            localId: Value(IdGenerator.newId()),
            journalLocalId: Value(reversalId),
            accountId: Value(l.accountId),
            accountCode: Value(l.accountCode),
            accountName: Value(l.accountName),
            direction: Value(l.direction),
            amountPaise: Value(l.amountPaise),
            narration: Value(l.narration),
            sortOrder: Value(i),
          ),
        );
      }
      await _localDs.upsertLines(companions);

      // Queue sync operation for the reversal.
      // We encode it as a full journal.posted event of a reversal entry.
      // (The sync event is structurally identical; sourceType distinguishes it.)
      final payload = _buildReversalPayload(
        reversalId,
        cmd,
        deviceId,
        companyId,
        now,
        reversalLines,
        header,
      );
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(IdGenerator.newId()),
              entityType: const Value('journal'),
              entityLocalId: Value(reversalId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              financialYearId: const Value(null),
              operationType: const Value('reverse'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('journal', 'reverse', reversalId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await getJournal(reversalId))!;
  }

  @override
  Future<void> retrySync(String localId) async {
    await (_db.update(_db.syncOperations)..where(
          (r) =>
              r.entityLocalId.equals(localId) &
              r.entityType.equals('journal') &
              r.status.equals(SyncStatus.failed.name),
        ))
        .write(
          SyncOperationsCompanion(
            status: Value(SyncStatus.pending.name),
            nextAttemptAt: const Value(null),
            lastError: const Value(null),
          ),
        );
    await (_db.update(
      _db.journalEntries,
    )..where((r) => r.localId.equals(localId))).write(
      JournalEntriesCompanion(
        syncStatus: Value(SyncStatus.pending.name),
        syncError: const Value(null),
      ),
    );
  }

  @override
  Future<void> resolveConflict(String localId) async {
    final journal = await _localDs.getJournal(localId);
    if (journal == null) {
      throw ValidationException('Journal entry not found: $localId');
    }

    await _db.transaction(() async {
      await (_db.delete(_db.syncOperations)..where(
            (r) =>
                r.entityType.equals('journal') &
                r.entityLocalId.equals(localId) &
                r.status.equals(SyncStatus.conflict.name),
          ))
          .go();
      await (_db.delete(_db.syncConflicts)..where(
            (r) =>
                r.entityType.equals('journal') &
                r.entityLocalId.equals(localId),
          ))
          .go();
      await (_db.update(
        _db.journalEntries,
      )..where((r) => r.localId.equals(localId))).write(
        const JournalEntriesCompanion(
          syncStatus: Value('synced'),
          isDirty: Value(false),
          syncError: Value(null),
        ),
      );
    });

    await _syncEngine.runPullCycle(companyId: journal.companyId);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _validateDraftCommand(CreateJournalCommand cmd) {
    if (cmd.entryDate.isEmpty || DateTime.tryParse(cmd.entryDate) == null) {
      throw const ValidationException('Enter a valid posting date.');
    }
    if (cmd.description.trim().isEmpty) {
      throw const ValidationException('Enter a journal narration.');
    }
    if (cmd.lines.length < 2) {
      throw const ValidationException(
        'A journal entry requires at least two lines.',
      );
    }
  }

  String _buildReversalPayload(
    String reversalId,
    ReverseJournalCommand cmd,
    String deviceId,
    String companyId,
    DateTime now,
    List<_ReversalLine> lines,
    JournalEntry original,
  ) {
    final linesPayload = lines.map((l) {
      final money = Money.fromPaise(l.amountPaise);
      return {
        'account_id': l.accountId,
        'account_code': l.accountCode,
        'account_name': l.accountName,
        'direction': l.direction,
        if (l.direction == 'DEBIT') 'debit_micros': money.toBackendMicros(),
        if (l.direction == 'CREDIT') 'credit_micros': money.toBackendMicros(),
        if (l.narration != null && l.narration!.isNotEmpty)
          'narration': l.narration,
      };
    }).toList();

    return jsonEncode({
      'event_id': reversalId,
      'company_id': companyId,
      'device_id': deviceId,
      'aggregate_type': 'journal',
      'aggregate_id': reversalId,
      'event_type': 'journal.reversed',
      'event_version': 1,
      'occurred_at': now.toIso8601String(),
      'payload': {
        'entry_date': cmd.reversalDate,
        'description': cmd.description.isNotEmpty
            ? cmd.description
            : 'Reversal of ${original.description}',
        'narration': cmd.description.isNotEmpty
            ? cmd.description
            : 'Reversal of ${original.description}',
        'source_type': 'JOURNAL_REVERSAL',
        'reversed_journal_id':
            (original.remoteId != null && original.remoteId!.isNotEmpty)
            ? original.remoteId
            : original.localId,
        'lines': linesPayload,
      },
    });
  }
}

class _ReversalLine {
  const _ReversalLine({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.direction,
    required this.amountPaise,
    this.narration,
  });
  final String accountId;
  final String accountCode;
  final String accountName;
  final String direction;
  final int amountPaise;
  final String? narration;
}
