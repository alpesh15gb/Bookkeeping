/// Mapper between the Drift row types and the domain [JournalEntryEntity].
///
/// The mapper handles all conversions between:
/// - Drift row objects ([JournalEntry] + [JournalLine]) ↔ domain entities.
/// - Domain entities ↔ sync-event payloads (JSON for the outbox).
/// - Backend response JSON ↔ [JournalEntryEntity] (post pull-sync).
///
/// Amount encoding:
/// - Local SQLite: INTEGER paise via [Money.fromPaise] / [Money.toPaise].
/// - Backend micros: via [Money.fromBackendMicros] / [Money.toBackendMicros].
///
/// **Never** convert amounts directly in notifiers, screens, or services.
library;

import 'dart:convert';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/sync/journal_lifecycle_status.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/core/utils/money.dart';
import 'package:apexbooks/features/accounting/journal/models/direction.dart';
import 'package:apexbooks/features/journals/domain/commands/journal_commands.dart';
import 'package:apexbooks/features/journals/domain/entities/journal_entity.dart';

class JournalMapper {
  JournalMapper._();

  // ── Drift row → domain entity ─────────────────────────────────────────────

  static JournalEntryEntity toDomain(
    JournalEntry row,
    List<JournalLine> lineRows,
  ) {
    return JournalEntryEntity(
      localId: row.localId,
      remoteId: row.remoteId,
      companyId: row.companyId,
      entryDate: row.entryDate,
      referenceNumber: row.referenceNumber,
      description: row.description,
      sourceType: row.sourceType,
      lifecycleStatus: JournalLifecycleStatus.fromName(row.lifecycleStatus),
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == row.syncStatus,
        orElse: () => SyncStatus.localOnly,
      ),
      localRevision: row.localRevision,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastSyncedAt: row.lastSyncedAt,
      syncError: row.syncError,
      lines: lineRows.map((l) => _lineToDomain(l, row.localId)).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );
  }

  static JournalLineEntity _lineToDomain(
    JournalLine row,
    String journalLocalId,
  ) {
    return JournalLineEntity(
      localId: row.localId,
      journalLocalId: journalLocalId,
      accountId: row.accountId,
      accountCode: row.accountCode,
      accountName: row.accountName,
      direction: Direction.fromString(row.direction),
      amount: Money.fromPaise(row.amountPaise),
      sortOrder: row.sortOrder,
      narration: row.narration,
    );
  }

  // ── Command → outbox sync-event payload ───────────────────────────────────

  /// Builds the JSON payload for a journal sync event.
  ///
  /// This is the payload stored in [SyncOperations.payload] and sent to
  /// `POST /apexbooks/sync/push`.
  static String toCreatePayloadJson(
    CreateJournalCommand cmd,
    String localId,
    String deviceId,
    DateTime occurredAt,
    String companyId, {
    String eventType = 'journal.posted',
    String? eventId,
  }) {
    // Amount encoding: paise → backend micros (10,000 micros = ₹1).
    final List<Map<String, dynamic>> linesPayload = [];
    for (int i = 0; i < cmd.lines.length; i++) {
      final line = cmd.lines[i];
      final money = Money.fromRupees(line.amount); // existing model uses double
      linesPayload.add({
        'account_id': line.accountId,
        'account_code': line.accountCode,
        'account_name': line.accountName,
        'direction': line.direction.value,
        if (line.direction.isDebit) 'debit_micros': money.toBackendMicros(),
        if (line.direction.isCredit) 'credit_micros': money.toBackendMicros(),
        if (line.narration != null && line.narration!.isNotEmpty)
          'narration': line.narration,
      });
    }

    final event = {
      'event_id': eventId ?? localId,
      'company_id': companyId,
      'device_id': deviceId,
      'aggregate_type': 'journal',
      'aggregate_id': localId,
      'event_type': eventType,
      'event_version': 1,
      'occurred_at': occurredAt.toIso8601String(),
      'payload': {
        'entry_date': cmd.entryDate,
        if (cmd.referenceNumber.isNotEmpty) ...{
          'reference_number': cmd.referenceNumber,
          'voucher_number': cmd.referenceNumber,
        },
        'description': cmd.description,
        'narration': cmd.description,
        'lines': linesPayload,
      },
    };
    return jsonEncode(event);
  }

  static String toUpdatePayloadJson(
    UpdateJournalCommand command, {
    required String deviceId,
    required String actorId,
    required DateTime occurredAt,
    required String eventId,
  }) {
    final payload =
        jsonDecode(
              toCreatePayloadJson(
                CreateJournalCommand(
                  companyId: command.companyId,
                  entryDate: command.entryDate,
                  referenceNumber: command.referenceNumber,
                  description: command.description,
                  lines: command.lines,
                ),
                command.localId,
                deviceId,
                occurredAt,
                command.companyId,
                eventId: eventId,
              ),
            )
            as Map<String, dynamic>;
    payload['event_type'] = 'journal.updated';
    payload['actor_id'] = actorId;
    return jsonEncode(payload);
  }

  // ── Backend pull-event → domain update ───────────────────────────────────

  /// Extracts a [remoteId] from a pull-event acknowledgement.
  ///
  /// The `/apexbooks/sync/push` response returns an ack per event:
  /// ```json
  /// { "event_id": "<uuid>", "server_sequence": 42, "duplicate": false }
  /// ```
  static String? extractRemoteIdFromAck(Map<String, dynamic> ack) {
    // The server stores aggregate_id as the entity's ID.
    // For journals, aggregate_id == the submitted event_id == localId.
    // The server assigns its own UUID which is returned in the full pull.
    return ack['server_id']?.toString();
  }
}
