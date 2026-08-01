/// Pull-event applicators for reference data (accounts + contacts).
///
/// Registered with [SyncEngine.registerPullApplicator] at startup so the
/// pull cycle can apply `account.created`, `account.updated`,
/// `party.created`, and `party.updated` events to the local Drift tables.
///
/// ## Idempotency
/// Each event carries the server's `aggregate_id`.  The applicator uses
/// `(companyId, aggregate_id)` as a unique constraint — replaying the same
/// event creates a no-op upsert, not a duplicate row.
library;

import 'package:drift/drift.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/core/utils/money.dart';
import 'sync_engine.dart';

/// Registers reference-data pull applicators on [engine].
///
/// Call this once during provider initialisation, before the scheduler starts
/// pulling.
void registerReferencePullApplicators(SyncEngine engine, AppDatabase db) {
  // ── Account events ──────────────────────────────────────────────────────

  engine.registerPullApplicator('account.created', (event) async {
    await _upsertAccount(db, event);
    return true;
  });

  engine.registerPullApplicator('account.updated', (event) async {
    await _upsertAccount(db, event);
    return true;
  });

  // ── Contact / party events ──────────────────────────────────────────────

  engine.registerPullApplicator('party.created', (event) async {
    await _upsertContact(db, event);
    return true;
  });

  engine.registerPullApplicator('party.updated', (event) async {
    await _upsertContact(db, event);
    return true;
  });

  engine.registerPullApplicator('item.created', (event) async {
    await _upsertProduct(db, event);
    return true;
  });

  engine.registerPullApplicator('item.updated', (event) async {
    await _upsertProduct(db, event);
    return true;
  });

  // ── Journal events ─────────────────────────────────────────────────────────

  for (final eventType in const [
    'journal.created',
    'journal.updated',
    'journal.posted',
    'journal.reversed',
  ]) {
    engine.registerPullApplicator(eventType, (event) async {
      await _upsertJournal(db, event);
      return true;
    });
  }

  for (final eventType in const [
    'branch.created',
    'warehouse.created',
    'money_account.created',
    'stock.transferred',
    'company.settings.updated',
    // Backend can emit these when another device pushes them. The client has
    // no per-aggregate applicator yet, but the pull cycle FAILS CLOSED on any
    // unknown event type (checkpoint not advanced → permanent pull deadlock).
    // Acknowledging them here unblocks the pipeline. Cross-device application
    // of these aggregates is tracked as a known limitation.
    'bank_statement.imported',
    'purchase_receipt.posted',
    'purchase_invoice.posted',
    'sales_delivery.posted',
    'sales_return.posted',
    'purchase_return.posted',
    'credit_note.posted',
    'debit_note.posted',
  ]) {
    engine.registerPullApplicator(eventType, (_) async => true);
  }
}

// ── Account applicator ────────────────────────────────────────────────────────

Future<void> _upsertAccount(AppDatabase db, Map<String, dynamic> event) async {
  final payload = event['payload'] as Map<String, dynamic>? ?? {};
  final companyId = _str(event, 'company_id');
  final aggregateId = _str(event, 'aggregate_id');
  final remoteId = payload['id'] as String? ?? aggregateId;

  if (remoteId.isEmpty || companyId.isEmpty) return;

  final now = DateTime.now().toUtc();
  final code = _str(payload, 'code');
  final name = _str(payload, 'name');
  final accountType = _mapAccountType(payload['account_type']?.toString());

  await db
      .into(db.accounts)
      .insertOnConflictUpdate(
        AccountsCompanion(
          localId: Value(remoteId), // server ID doubles as localId for ref data
          remoteId: Value(remoteId),
          companyId: Value(companyId),
          code: Value(code),
          name: Value(name),
          accountType: Value(accountType),
          parentRemoteId: Value(_nullableStr(payload, 'parent_id')),
          accountGroup: Value(_nullableStr(payload, 'account_group')),
          isActive: Value(payload['is_active'] as bool? ?? true),
          openingBalancePaise: Value(_parsePaise(payload['opening_balance'])),
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
}

// ── Contact applicator ────────────────────────────────────────────────────────

Future<void> _upsertContact(AppDatabase db, Map<String, dynamic> event) async {
  final payload = event['payload'] as Map<String, dynamic>? ?? {};
  final companyId = _str(event, 'company_id');
  final aggregateId = _str(event, 'aggregate_id');
  final remoteId = payload['id'] as String? ?? aggregateId;

  if (remoteId.isEmpty || companyId.isEmpty) return;

  final now = DateTime.now().toUtc();
  final kind = payload['kind']?.toString() ?? 'other';
  final contactType = kind == 'customer'
      ? 'customer'
      : kind == 'supplier'
      ? 'vendor'
      : 'both';

  await db
      .into(db.contacts)
      .insertOnConflictUpdate(
        ContactsCompanion(
          localId: Value(remoteId),
          remoteId: Value(remoteId),
          companyId: Value(companyId),
          name: Value(_str(payload, 'name')),
          email: Value(_nullableStr(payload, 'email')),
          phone: Value(_nullableStr(payload, 'phone')),
          contactType: Value(contactType),
          gstin: Value(_nullableStr(payload, 'gstin')),
          stateCode: Value(_nullableStr(payload, 'state_code')),
          isActive: Value(payload['is_active'] as bool? ?? true),
          openingBalancePaise: Value(_parsePaise(payload['opening_balance'])),
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
}

Future<void> _upsertProduct(AppDatabase db, Map<String, dynamic> event) async {
  final payload = event['payload'] as Map<String, dynamic>? ?? {};
  final companyId = _str(event, 'company_id');
  final remoteId = _str(event, 'aggregate_id');
  if (remoteId.isEmpty || companyId.isEmpty) return;
  final now = DateTime.now().toUtc();
  await db
      .into(db.stockItems)
      .insertOnConflictUpdate(
        StockItemsCompanion(
          localId: Value(remoteId),
          remoteId: Value(remoteId),
          companyId: Value(companyId),
          name: Value(_str(payload, 'name')),
          sku: Value(_nullableStr(payload, 'sku')),
          unit: Value(
            _str(payload, 'unit').isEmpty ? 'PCS' : _str(payload, 'unit'),
          ),
          hsnSac: Value(_nullableStr(payload, 'hsn')),
          currentQuantity: Value(
            (_asInt(payload['opening_quantity_micros']) / 10000).toString(),
          ),
          unitCostPaise: Value(
            Money.fromBackendMicros(
              _asInt(payload['purchase_price_micros']),
            ).toPaise(),
          ),
          salesPricePaise: Value(
            Money.fromBackendMicros(
              _asInt(payload['sale_price_micros']),
            ).toPaise(),
          ),
          gstRateBasisPoints: Value(
            _asInt(payload['default_tax_rate_basis_points']),
          ),
          isActive: Value(payload['is_active'] as bool? ?? true),
          syncStatus: const Value('synced'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
}

// ── Journal applicator ─────────────────────────────────────────────────────────

Future<void> _upsertJournal(AppDatabase db, Map<String, dynamic> event) async {
  final payload = event['payload'] as Map<String, dynamic>? ?? {};
  final companyId = _str(event, 'company_id');
  final aggregateId = _str(event, 'aggregate_id');
  if (aggregateId.isEmpty || companyId.isEmpty) return;

  final now = DateTime.now().toUtc();
  final serverSequence = _asInt(event['server_sequence']);
  final existing = await (db.select(
    db.journalEntries,
  )..where((row) => row.localId.equals(aggregateId))).getSingleOrNull();
  if (existing?.remoteRevision != null &&
      serverSequence > 0 &&
      serverSequence <= existing!.remoteRevision!) {
    return;
  }

  final eventType = _str(event, 'event_type');
  final isReversal = eventType == 'journal.reversed';
  final lifecycle =
      eventType == 'journal.created' || eventType == 'journal.updated'
      ? 'draft'
      : 'posted';
  final linesPayload = payload['lines'] as List? ?? const [];

  await db
      .into(db.journalEntries)
      .insertOnConflictUpdate(
        JournalEntriesCompanion(
          localId: Value(aggregateId),
          remoteId: Value(aggregateId),
          companyId: Value(companyId),
          entryDate: Value(_str(payload, 'entry_date')),
          referenceNumber: Value(
            _nullableStr(payload, 'reference_number') ??
                _nullableStr(payload, 'voucher_number'),
          ),
          description: Value(
            _str(payload, 'description').isNotEmpty
                ? _str(payload, 'description')
                : _str(payload, 'narration'),
          ),
          sourceType: Value(
            _str(payload, 'source_type').isEmpty
                ? 'MANUAL'
                : _str(payload, 'source_type'),
          ),
          lifecycleStatus: Value(lifecycle),
          syncStatus: Value(SyncStatus.synced.name),
          isDirty: const Value(false),
          originDeviceId: Value(_str(event, 'device_id')),
          lastSyncedAt: Value(now),
          remoteRevision: serverSequence > 0
              ? Value(serverSequence)
              : const Value.absent(),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        ),
      );

  await (db.delete(
    db.journalLines,
  )..where((line) => line.journalLocalId.equals(aggregateId))).go();

  final companions = <JournalLinesCompanion>[];
  for (int i = 0; i < linesPayload.length; i++) {
    final line = linesPayload[i] as Map<String, dynamic>;
    final side = _lineSide(line);
    final amountMicros = _lineAmountMicros(line, side);
    if (side.isEmpty || amountMicros <= 0) continue;

    final accountId = _str(line, 'account_id');
    final account =
        await (db.select(db.accounts)..where(
              (a) => a.localId.equals(accountId) | a.remoteId.equals(accountId),
            ))
            .getSingleOrNull();

    companions.add(
      JournalLinesCompanion(
        localId: Value(IdGenerator.newId()),
        journalLocalId: Value(aggregateId),
        accountId: Value(accountId),
        accountCode: Value(
          _str(line, 'account_code').isNotEmpty
              ? _str(line, 'account_code')
              : (account?.code ?? ''),
        ),
        accountName: Value(
          _str(line, 'account_name').isNotEmpty
              ? _str(line, 'account_name')
              : (account?.name ?? ''),
        ),
        direction: Value(side),
        amountPaise: Value(Money.fromBackendMicros(amountMicros).toPaise()),
        narration: Value(
          _nullableStr(line, 'narration') ?? _nullableStr(line, 'memo'),
        ),
        sortOrder: Value(i),
      ),
    );
  }

  if (companions.isNotEmpty) {
    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(db.journalLines, companions);
    });
  }

  // Reversal events carry the original aggregate id.  Mark the original
  // local journal reversed while retaining the reversal as its own posted
  // journal, so reports and audit history remain complete.
  if (isReversal) {
    final originalId = _nullableStr(payload, 'reversed_journal_id');
    if (originalId != null && originalId.isNotEmpty) {
      await (db.update(
        db.journalEntries,
      )..where((row) => row.localId.equals(originalId))).write(
        JournalEntriesCompanion(
          lifecycleStatus: const Value('reversed'),
          updatedAt: Value(now),
        ),
      );
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _str(Map<String, dynamic> m, String key) => (m[key]?.toString()) ?? '';

String? _nullableStr(Map<String, dynamic> m, String key) => m[key]?.toString();

String _lineSide(Map<String, dynamic> line) {
  final direction = _str(line, 'direction').toUpperCase();
  if (direction == 'DEBIT' || direction == 'CREDIT') return direction;
  final debit = _asInt(line['debit_micros']);
  final credit = _asInt(line['credit_micros']);
  if (debit > 0) return 'DEBIT';
  if (credit > 0) return 'CREDIT';
  return '';
}

int _lineAmountMicros(Map<String, dynamic> line, String side) {
  final sideValue = side == 'DEBIT'
      ? _asInt(line['debit_micros'])
      : _asInt(line['credit_micros']);
  if (sideValue > 0) return sideValue;
  return _asInt(line['amount_micros']);
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ?? 0;
}

String _mapAccountType(String? type) {
  switch (type?.toLowerCase()) {
    case 'asset':
      return 'asset';
    case 'liability':
      return 'liability';
    case 'equity':
      return 'equity';
    case 'income':
    case 'revenue':
      return 'revenue';
    case 'expense':
      return 'expense';
    default:
      return 'asset';
  }
}

/// Parses an amount from a pull event payload into integer paise.
/// The backend may send amounts as Decimal strings or integers.
int _parsePaise(dynamic value) {
  if (value == null) return 0;
  if (value is int) {
    // Backend Numeric(15,4) — assume integer represents rupees (no decimals).
    return Money.fromRupees(value).toPaise();
  }
  if (value is double) return Money.fromRupees(value).toPaise();
  if (value is String) {
    final cleaned = value.replaceAll(',', '');
    final d = double.tryParse(cleaned);
    if (d != null) return Money.fromRupees(d).toPaise();
  }
  return 0;
}
