/// Implementation of [PaymentRepository] using the transactional outbox pattern.
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
import '../../domain/commands/payment_commands.dart';
import '../../domain/entities/payment_entity.dart';
import '../../domain/repositories/payment_repository.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  PaymentRepositoryImpl({
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
    _syncEngine.registerPusher('payment', (op) => _pushPayment(op));
    _syncEngine.registerPullApplicator(
      'money_transaction.posted',
      _applyPulledPayment,
    );
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  // ── Read ──────────────────────────────────────────────────────────────────

  @override
  Stream<List<PaymentEntity>> watchPayments({String? companyId}) async* {
    final query = _db.select(_db.payments)
      ..where((p) => p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    if (companyId != null) query.where((p) => p.companyId.equals(companyId));

    await for (final rows in query.watch()) {
      yield rows.map(_toEntity).toList();
    }
  }

  @override
  Future<PaymentEntity?> getPayment(String localId) async {
    final row =
        await (_db.select(_db.payments)
              ..where((p) => p.localId.equals(localId) & p.deletedAt.isNull()))
            .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  // ── Draft ─────────────────────────────────────────────────────────────────

  @override
  Future<PaymentEntity> saveDraft(SavePaymentDraftCommand cmd) async {
    final localId = IdGenerator.newId();
    final now = DateTime.now().toUtc();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();

    await _db
        .into(_db.payments)
        .insert(
          PaymentsCompanion(
            localId: Value(localId),
            companyId: Value(companyId),
            paymentType: Value(cmd.paymentType),
            paymentDate: Value(cmd.paymentDate),
            referenceNumber: Value(cmd.referenceNumber),
            contactId: Value(cmd.contactId),
            contactName: Value(cmd.contactName),
            paymentMode: Value(cmd.paymentMode),
            accountId: Value(cmd.accountId),
            amountPaise: Value(cmd.amountPaise),
            description: Value(cmd.description),
            lifecycleStatus: const Value('draft'),
            syncStatus: const Value('localOnly'),
            createdAt: Value(now),
            updatedAt: Value(now),
            originDeviceId: Value(await _deviceIdProvider()),
          ),
        );

    return (await getPayment(localId))!;
  }

  // ── Post (journal + outbox) ──────────────────────────────────────────────

  @override
  Future<PaymentEntity> post(PostPaymentCommand cmd) async {
    final payment = await getPayment(cmd.localId);
    if (payment == null) {
      throw const ValidationException('Payment not found.');
    }
    if (!payment.isDraft) {
      throw const ValidationException('Only draft payments can be posted.');
    }
    if (payment.amountPaise <= 0) {
      throw const ValidationException(
        'Payment amount must be greater than zero.',
      );
    }

    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final now = DateTime.now().toUtc();
    final journalLocalId = IdGenerator.newId();
    final opId = IdGenerator.newId();
    final idempotencyKey = IdGenerator.actionKey(
      'payment',
      'post',
      cmd.localId,
    );
    final contact =
        await (_db.select(_db.contacts)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  (row.localId.equals(payment.contactId) |
                      row.remoteId.equals(payment.contactId)) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (contact == null) {
      throw const ValidationException(
        'The selected contact is not available for this company.',
      );
    }
    final contactAccountId = payment.isReceipt
        ? contact.receivableAccountId
        : contact.payableAccountId;
    if (contactAccountId == null || contactAccountId.isEmpty) {
      throw ValidationException(
        payment.isReceipt
            ? 'Customer receivable account is not available. Connect once to refresh master data.'
            : 'Vendor payable account is not available. Connect once to refresh master data.',
      );
    }
    final moneyAccount =
        await (_db.select(_db.accounts)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  (row.localId.equals(payment.accountId) |
                      row.remoteId.equals(payment.accountId)) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (moneyAccount == null || moneyAccount.accountType != 'asset') {
      throw const ValidationException(
        'Select an active cash or bank account for this company.',
      );
    }

    await _db.transaction(() async {
      // 1. Update payment lifecycle.
      await (_db.update(
        _db.payments,
      )..where((p) => p.localId.equals(cmd.localId))).write(
        PaymentsCompanion(
          lifecycleStatus: const Value('posted'),
          syncStatus: const Value('pending'),
          isDirty: const Value(true),
          updatedAt: Value(now),
        ),
      );

      // 2. Create journal entry for the payment.
      // Receipt: DEBIT bank/cash account, CREDIT contact account.
      // Payment: DEBIT contact/expense account, CREDIT bank/cash account.
      final debitAccountId = payment.isReceipt
          ? payment
                .accountId // bank/cash receives money
          : contactAccountId; // vendor payable receives debit
      final creditAccountId = payment.isReceipt
          ? contactAccountId // customer receivable credited
          : payment.accountId; // bank/cash credited

      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(payment.paymentDate),
              referenceNumber: Value(payment.referenceNumber),
              description: Value(
                '${payment.isReceipt ? "Receipt" : "Payment"}: ${payment.contactName}',
              ),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'), // journal is local-only
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );

      // Debit line.
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: Value(debitAccountId),
              accountCode: const Value(''),
              accountName: Value(
                payment.isReceipt ? 'Bank Account' : payment.contactName,
              ),
              direction: const Value('DEBIT'),
              amountPaise: Value(payment.amountPaise),
              sortOrder: const Value(0),
            ),
          );

      // Credit line.
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: Value(creditAccountId),
              accountCode: const Value(''),
              accountName: Value(
                payment.isReceipt ? payment.contactName : 'Bank Account',
              ),
              direction: const Value('CREDIT'),
              amountPaise: Value(payment.amountPaise),
              sortOrder: const Value(1),
            ),
          );

      // 3. Queue sync operation.
      final payloadJson = _buildSyncPayload(payment, companyId, deviceId, now);
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('payment'),
              entityLocalId: Value(cmd.localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payloadJson),
              idempotencyKey: Value(idempotencyKey),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await getPayment(cmd.localId))!;
  }

  // ── Sync ─────────────────────────────────────────────────────────────────

  @override
  Future<void> retrySync(String localId) async {
    await (_db.update(_db.syncOperations)..where(
          (o) =>
              o.entityLocalId.equals(localId) &
              o.entityType.equals('payment') &
              o.status.equals(SyncStatus.failed.name),
        ))
        .write(
          const SyncOperationsCompanion(
            status: Value('pending'),
            nextAttemptAt: Value(null),
            lastError: Value(null),
          ),
        );
    await (_db.update(
      _db.payments,
    )..where((p) => p.localId.equals(localId))).write(
      const PaymentsCompanion(
        syncStatus: Value('pending'),
        syncError: Value(null),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  PaymentEntity _toEntity(Payment row) => PaymentEntity(
    localId: row.localId,
    remoteId: row.remoteId,
    companyId: row.companyId,
    paymentType: row.paymentType,
    paymentDate: row.paymentDate,
    referenceNumber: row.referenceNumber,
    contactId: row.contactId,
    contactName: row.contactName,
    paymentMode: row.paymentMode,
    accountId: row.accountId,
    amountPaise: row.amountPaise,
    description: row.description,
    lifecycleStatus: row.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    localRevision: row.localRevision,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    lastSyncedAt: row.lastSyncedAt,
    syncError: row.syncError,
  );

  String _buildSyncPayload(
    PaymentEntity p,
    String companyId,
    String deviceId,
    DateTime now,
  ) {
    return jsonEncode({
      'event_id': p.localId,
      'company_id': companyId,
      'device_id': deviceId,
      'aggregate_type': 'money_transaction',
      'aggregate_id': p.localId,
      'event_type': 'money_transaction.posted',
      'event_version': 1,
      'occurred_at': now.toIso8601String(),
      'payload': {
        'kind': p.isReceipt ? 'receipt' : 'payment',
        'payment_date': p.paymentDate,
        'contact_id': p.contactId,
        'contact_name': p.contactName,
        'payment_mode': p.paymentMode,
        'account_id': p.accountId,
        'amount_micros': p.amountPaise * 100,
        'reference': p.referenceNumber,
        'narration': p.description,
      },
    });
  }

  Future<bool> _applyPulledPayment(Map<String, dynamic> event) async {
    final payload =
        event['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final kind = payload['kind']?.toString() ?? '';
    if (kind != 'receipt' && kind != 'payment') return false;
    final companyId = event['company_id']?.toString() ?? '';
    final paymentId = event['aggregate_id']?.toString() ?? '';
    final contactId = payload['contact_id']?.toString() ?? '';
    final accountId = payload['account_id']?.toString() ?? '';
    if (companyId.isEmpty ||
        paymentId.isEmpty ||
        contactId.isEmpty ||
        accountId.isEmpty) {
      throw const FormatException('Pulled payment identity is incomplete.');
    }
    final existing = await (_db.select(
      _db.payments,
    )..where((row) => row.localId.equals(paymentId))).getSingleOrNull();
    if (existing?.isDirty == true) {
      throw StateError('Pulled payment conflicts with an unsynced local edit.');
    }
    final contact =
        await (_db.select(_db.contacts)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  (row.localId.equals(contactId) |
                      row.remoteId.equals(contactId)),
            ))
            .getSingleOrNull();
    if (contact == null) {
      throw StateError('Pulled payment contact is not available locally.');
    }
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.payments)
        .insertOnConflictUpdate(
          PaymentsCompanion(
            localId: Value(paymentId),
            remoteId: Value(paymentId),
            companyId: Value(companyId),
            paymentType: Value(kind == 'receipt' ? 'RECEIPT' : 'PAYMENT'),
            paymentDate: Value(
              payload['payment_date']?.toString() ??
                  event['occurred_at']?.toString().split('T').first ??
                  '',
            ),
            referenceNumber: Value(payload['reference']?.toString()),
            contactId: Value(contactId),
            contactName: Value(
              payload['contact_name']?.toString() ?? contact.name,
            ),
            paymentMode: Value(payload['payment_mode']?.toString() ?? 'BANK'),
            accountId: Value(accountId),
            amountPaise: Value(_paymentMicrosToPaise(payload['amount_micros'])),
            description: Value(payload['narration']?.toString()),
            lifecycleStatus: const Value('posted'),
            syncStatus: Value(SyncStatus.synced.name),
            remoteRevision: Value(_paymentInt(event['server_sequence'])),
            isDirty: const Value(false),
            createdAt: Value(existing?.createdAt ?? now),
            updatedAt: Value(now),
            lastSyncedAt: Value(now),
            originDeviceId: Value(event['device_id']?.toString() ?? ''),
          ),
        );
    return true;
  }

  Future<SyncPushResult> _pushPayment(OutboxRecord op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    try {
      final res = await _dio.post(
        '/apexbooks/sync/push',
        data: {
          'events': [payload],
        },
        options: Options(headers: {'Idempotency-Key': op.idempotencyKey}),
      );
      return parseSyncPushResponse(res.data, payload, entityLabel: 'payment');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 422) {
        throw const PermanentSyncException(
          'Validation error',
          userAction: 'Review the payment for errors.',
        );
      }
      if (code == 409) {
        throw const ConflictException('Payment conflict.');
      }
      if (code != null && code >= 500) {
        throw RetryableSyncException('Server error ($code).');
      }
      throw RetryableSyncException('Network error.', cause: e);
    }
  }
}

int _paymentMicrosToPaise(Object? value) {
  final micros = value is num
      ? value.round()
      : int.tryParse(value?.toString() ?? '') ?? 0;
  return (micros / 100).round();
}

int? _paymentInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.round() : int.tryParse(value.toString());
}
