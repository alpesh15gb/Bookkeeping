library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/ids/id_generator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../core/sync/sync_operation.dart';
import '../../../../core/sync/sync_status.dart';
import '../../domain/commands/credit_debit_commands.dart';
import '../../domain/entities/credit_debit_entities.dart';
import '../../domain/repositories/credit_debit_repository.dart';

class CreditDebitRepositoryImpl implements CreditDebitRepository {
  CreditDebitRepositoryImpl({
    required AppDatabase db,
    required SyncEngine syncEngine,
    required Dio dio,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() companyIdProvider,
    required Future<String> Function() actorIdProvider,
  }) : _db = db,
       _syncEngine = syncEngine,
       _dio = dio,
       _deviceIdProvider = deviceIdProvider,
       _companyIdProvider = companyIdProvider,
       _actorIdProvider = actorIdProvider {
    _syncEngine.registerPusher('credit_note', (op) => _push(op));
    _syncEngine.registerPusher('debit_note', (op) => _push(op));
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  @override
  Future<CreditNoteEntity> postCreditNote(PostCreditNoteCommand cmd) async {
    final cid = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final did = await _deviceIdProvider();
    final aid = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final localId = IdGenerator.newId();
    final jlId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    if (cmd.totalPaise <= 0) {
      throw const ValidationException('Amount must be > 0.');
    }

    await _db.transaction(() async {
      var alloc =
          await (_db.select(_db.numberAllocations)..where(
                (a) =>
                    a.companyId.equals(cid) &
                    a.deviceId.equals(did) &
                    a.series.equals('CREDIT_NOTE') &
                    a.documentType.equals('CREDIT_NOTE') &
                    a.isActive.equals(true),
              ))
              .getSingleOrNull();
      alloc ??=
          await (_db.select(_db.numberAllocations)..where(
                (a) =>
                    a.companyId.equals(cid) &
                    a.deviceId.equals(did) &
                    a.series.equals('SALES') &
                    a.documentType.equals('CREDIT_NOTE') &
                    a.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (alloc == null ||
          (alloc.toNum - alloc.fromNum + 1 - alloc.used) <= 0) {
        throw const ValidationException('No credit note number available.');
      }
      final allocNonNull = alloc;
      final num_ = allocNonNull.fromNum + allocNonNull.used;
      final allocDbId = allocNonNull.id;
      await (_db.update(
        _db.numberAllocations,
      )..where((a) => a.id.equals(allocDbId))).write(
        NumberAllocationsCompanion(
          used: Value(allocNonNull.used + 1),
          updatedAt: Value(now),
        ),
      );

      await _db
          .into(_db.creditNotes)
          .insert(
            CreditNotesCompanion(
              localId: Value(localId),
              companyId: Value(cid),
              creditNoteDate: Value(cmd.creditNoteDate),
              customerId: Value(cmd.customerId),
              customerName: Value(cmd.customerName),
              number: Value(num_),
              allocationId: Value(allocNonNull.allocationId),
              sourceInvoiceLocalId: Value(cmd.sourceInvoiceLocalId),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              totalBeforeTaxPaise: Value(
                cmd.totalBeforeTaxPaise > 0
                    ? cmd.totalBeforeTaxPaise
                    : cmd.totalPaise,
              ),
              taxPaise: Value(cmd.taxPaise),
              totalPaise: Value(cmd.totalPaise),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(did),
            ),
          );
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(jlId),
              companyId: Value(cid),
              entryDate: Value(cmd.creditNoteDate),
              description: Value('Credit note #$num_: ${cmd.customerName}'),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(did),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(jlId),
              accountId: const Value('receivables'),
              accountCode: const Value(''),
              accountName: const Value('Accounts Receivable'),
              direction: const Value('CREDIT'),
              amountPaise: Value(cmd.totalPaise),
              sortOrder: const Value(0),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(jlId),
              accountId: const Value('revenue'),
              accountCode: const Value(''),
              accountName: const Value('Sales Revenue'),
              direction: const Value('DEBIT'),
              amountPaise: Value(cmd.totalPaise),
              sortOrder: const Value(0),
            ),
          );
      final payload = jsonEncode({
        'event_id': localId,
        'company_id': cid,
        'device_id': did,
        'aggregate_type': 'credit_note',
        'aggregate_id': localId,
        'event_type': 'credit_note.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'number': num_,
          'invoice_id': cmd.sourceInvoiceLocalId,
          'party_id': cmd.customerId,
          'customer_id': cmd.customerId,
          'customer_name': cmd.customerName,
          'credit_note_date': cmd.creditNoteDate,
          'total_paise': cmd.totalPaise,
          'subtotal_paise': cmd.totalBeforeTaxPaise,
          'tax_paise': cmd.taxPaise,
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('credit_note'),
              entityLocalId: Value(localId),
              companyId: Value(cid),
              actorId: Value(aid),
              deviceId: Value(did),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('credit_note', 'post', localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });
    return _cnEntity(
      await (_db.select(
        _db.creditNotes,
      )..where((r) => r.localId.equals(localId))).getSingle(),
    );
  }

  @override
  Future<DebitNoteEntity> postDebitNote(PostDebitNoteCommand cmd) async {
    final cid = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final did = await _deviceIdProvider();
    final aid = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final localId = IdGenerator.newId();
    final jlId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    if (cmd.totalPaise <= 0) {
      throw const ValidationException('Amount must be > 0.');
    }

    await _db.transaction(() async {
      var alloc =
          await (_db.select(_db.numberAllocations)..where(
                (a) =>
                    a.companyId.equals(cid) &
                    a.deviceId.equals(did) &
                    a.series.equals('DEBIT_NOTE') &
                    a.documentType.equals('DEBIT_NOTE') &
                    a.isActive.equals(true),
              ))
              .getSingleOrNull();
      alloc ??=
          await (_db.select(_db.numberAllocations)..where(
                (a) =>
                    a.companyId.equals(cid) &
                    a.deviceId.equals(did) &
                    a.series.equals('PURCHASE') &
                    a.documentType.equals('DEBIT_NOTE') &
                    a.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (alloc == null ||
          (alloc.toNum - alloc.fromNum + 1 - alloc.used) <= 0) {
        throw const ValidationException('No debit note number available.');
      }
      final allocNonNull = alloc;
      final num_ = allocNonNull.fromNum + allocNonNull.used;
      final allocDbId = allocNonNull.id;
      await (_db.update(
        _db.numberAllocations,
      )..where((a) => a.id.equals(allocDbId))).write(
        NumberAllocationsCompanion(
          used: Value(allocNonNull.used + 1),
          updatedAt: Value(now),
        ),
      );

      await _db
          .into(_db.debitNotes)
          .insert(
            DebitNotesCompanion(
              localId: Value(localId),
              companyId: Value(cid),
              debitNoteDate: Value(cmd.debitNoteDate),
              supplierId: Value(cmd.supplierId),
              supplierName: Value(cmd.supplierName),
              number: Value(num_),
              allocationId: Value(allocNonNull.allocationId),
              sourceInvoiceLocalId: Value(cmd.sourceInvoiceLocalId),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              totalBeforeTaxPaise: Value(
                cmd.totalBeforeTaxPaise > 0
                    ? cmd.totalBeforeTaxPaise
                    : cmd.totalPaise,
              ),
              taxPaise: Value(cmd.taxPaise),
              totalPaise: Value(cmd.totalPaise),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(did),
            ),
          );
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(jlId),
              companyId: Value(cid),
              entryDate: Value(cmd.debitNoteDate),
              description: Value('Debit note #$num_: ${cmd.supplierName}'),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(did),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(jlId),
              accountId: const Value('ap'),
              accountCode: const Value(''),
              accountName: const Value('Accounts Payable'),
              direction: const Value('DEBIT'),
              amountPaise: Value(cmd.totalPaise),
              sortOrder: const Value(0),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(jlId),
              accountId: const Value('purchases'),
              accountCode: const Value(''),
              accountName: const Value('Purchases'),
              direction: const Value('CREDIT'),
              amountPaise: Value(cmd.totalPaise),
              sortOrder: const Value(0),
            ),
          );
      final payload = jsonEncode({
        'event_id': localId,
        'company_id': cid,
        'device_id': did,
        'aggregate_type': 'debit_note',
        'aggregate_id': localId,
        'event_type': 'debit_note.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'number': num_,
          'bill_id': cmd.sourceInvoiceLocalId,
          'supplier_id': cmd.supplierId,
          'party_id': cmd.supplierId,
          'supplier_name': cmd.supplierName,
          'debit_note_date': cmd.debitNoteDate,
          'total_paise': cmd.totalPaise,
          'subtotal_paise': cmd.totalBeforeTaxPaise,
          'tax_paise': cmd.taxPaise,
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('debit_note'),
              entityLocalId: Value(localId),
              companyId: Value(cid),
              actorId: Value(aid),
              deviceId: Value(did),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('debit_note', 'post', localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });
    return _dnEntity(
      await (_db.select(
        _db.debitNotes,
      )..where((r) => r.localId.equals(localId))).getSingle(),
    );
  }

  @override
  Stream<List<CreditNoteEntity>> watchCreditNotes({String? companyId}) async* {
    final q = _db.select(_db.creditNotes)
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (companyId != null) q.where((r) => r.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows.map(_cnEntity).toList();
    }
  }

  @override
  Stream<List<DebitNoteEntity>> watchDebitNotes({String? companyId}) async* {
    final q = _db.select(_db.debitNotes)
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (companyId != null) q.where((r) => r.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows.map(_dnEntity).toList();
    }
  }

  CreditNoteEntity _cnEntity(CreditNote r) => CreditNoteEntity(
    localId: r.localId,
    companyId: r.companyId,
    creditNoteDate: r.creditNoteDate,
    customerId: r.customerId,
    customerName: r.customerName,
    number: r.number,
    allocationId: r.allocationId,
    sourceInvoiceLocalId: r.sourceInvoiceLocalId,
    referenceNumber: r.referenceNumber,
    description: r.description,
    totalPaise: r.totalPaise,
    lifecycleStatus: r.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == r.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: r.createdAt,
    syncError: r.syncError,
  );

  DebitNoteEntity _dnEntity(DebitNote r) => DebitNoteEntity(
    localId: r.localId,
    companyId: r.companyId,
    debitNoteDate: r.debitNoteDate,
    supplierId: r.supplierId,
    supplierName: r.supplierName,
    number: r.number,
    allocationId: r.allocationId,
    sourceInvoiceLocalId: r.sourceInvoiceLocalId,
    referenceNumber: r.referenceNumber,
    description: r.description,
    totalPaise: r.totalPaise,
    lifecycleStatus: r.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == r.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: r.createdAt,
    syncError: r.syncError,
  );

  Future<SyncPushResult> _push(OutboxRecord op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    try {
      final res = await _dio.post(
        '/apexbooks/sync/push',
        data: {
          'events': [payload],
        },
        options: Options(headers: {'Idempotency-Key': op.idempotencyKey}),
      );
      return parseSyncPushResponse(
        res.data,
        payload,
        entityLabel: op.entityType.replaceAll('_', ' '),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 422) {
        throw const PermanentSyncException('Validation error');
      }
      if (code != null && code >= 500) {
        throw RetryableSyncException('Server error ($code).');
      }
      throw RetryableSyncException('Network error.', cause: e);
    }
  }
}
