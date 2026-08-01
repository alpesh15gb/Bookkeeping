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
import '../../domain/commands/banking_commands.dart';
import '../../domain/entities/banking_entities.dart';
import '../../domain/repositories/banking_repository.dart';

class BankingRepositoryImpl implements BankingRepository {
  BankingRepositoryImpl({
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
    _syncEngine.registerPusher('bank_statement', (op) => _push(op));
    _syncEngine.registerPusher('reconciliation', (op) => _push(op));
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  @override
  Future<BankStatementEntity> importStatement(
    ImportStatementCommand cmd,
  ) async {
    final cid = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final did = await _deviceIdProvider();
    final aid = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final stmtId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    // Check for duplicate by (companyId, externalId) on first line if available.
    if (cmd.lines.isNotEmpty && cmd.lines.first.externalId != null) {
      final existing =
          await (_db.select(
                _db.bankStatementLines,
              )..where((l) => l.externalId.equals(cmd.lines.first.externalId!)))
              .getSingleOrNull();
      if (existing != null) {
        throw const ValidationException(
          'Statement already imported (duplicate external ID).',
        );
      }
    }

    await _db.transaction(() async {
      await _db
          .into(_db.bankStatements)
          .insert(
            BankStatementsCompanion(
              localId: Value(stmtId),
              companyId: Value(cid),
              bankAccountId: Value(cmd.bankAccountId),
              statementDate: Value(cmd.statementDate),
              openingBalance: Value(cmd.openingBalance),
              closingBalance: Value(cmd.closingBalance),
              importedAt: Value(now),
              createdAt: Value(now),
            ),
          );
      for (final l in cmd.lines) {
        await _db
            .into(_db.bankStatementLines)
            .insert(
              BankStatementLinesCompanion(
                localId: Value(IdGenerator.newId()),
                statementId: Value(stmtId),
                transactionDate: Value(l.transactionDate),
                description: Value(l.description),
                referenceNumber: Value(l.referenceNumber),
                amountPaise: Value(l.amountPaise),
                balancePaise: Value(l.balancePaise),
                externalId: Value(l.externalId),
              ),
            );
      }
      final payload = jsonEncode({
        'event_id': stmtId,
        'company_id': cid,
        'device_id': did,
        'aggregate_type': 'bank_statement',
        'aggregate_id': stmtId,
        'event_type': 'bank_statement.imported',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'bank_account_id': cmd.bankAccountId,
          'statement_date': cmd.statementDate,
          'opening_balance_micros': _amountToMicros(cmd.openingBalance),
          'closing_balance_micros': _amountToMicros(cmd.closingBalance),
          'lines': cmd.lines
              .map(
                (line) => {
                  'transaction_date': line.transactionDate,
                  'description': line.description,
                  'reference_number': line.referenceNumber,
                  'amount_micros': line.amountPaise * 100,
                  'balance_micros': line.balancePaise * 100,
                  'external_id': line.externalId,
                },
              )
              .toList(),
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('bank_statement'),
              entityLocalId: Value(stmtId),
              companyId: Value(cid),
              actorId: Value(aid),
              deviceId: Value(did),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('banking', 'import', stmtId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    final lines = cmd.lines
        .map(
          (l) => BankStatementLineEntity(
            localId: '',
            statementId: stmtId,
            transactionDate: l.transactionDate,
            description: l.description,
            referenceNumber: l.referenceNumber,
            amountPaise: l.amountPaise,
            balancePaise: l.balancePaise,
            externalId: l.externalId,
          ),
        )
        .toList();
    return BankStatementEntity(
      localId: stmtId,
      companyId: cid,
      bankAccountId: cmd.bankAccountId,
      statementDate: cmd.statementDate,
      openingBalance: cmd.openingBalance,
      closingBalance: cmd.closingBalance,
      lines: lines,
    );
  }

  @override
  Future<BankMatchEntity> matchLine(MatchStatementLineCommand cmd) async {
    final lid = IdGenerator.newId();
    await _db
        .into(_db.bankMatches)
        .insert(
          BankMatchesCompanion(
            localId: Value(lid),
            companyId: Value(cmd.companyId),
            statementLineLocalId: Value(cmd.statementLineLocalId),
            sourceType: Value(cmd.sourceType),
            sourceLocalId: Value(cmd.sourceLocalId),
            matchedAmountPaise: Value(cmd.matchedAmountPaise),
            createdAt: Value(DateTime.now().toUtc()),
          ),
        );
    await (_db.update(_db.bankStatementLines)
          ..where((l) => l.localId.equals(cmd.statementLineLocalId)))
        .write(const BankStatementLinesCompanion(isMatched: Value(true)));
    return BankMatchEntity(
      localId: lid,
      companyId: cmd.companyId,
      statementLineLocalId: cmd.statementLineLocalId,
      sourceType: cmd.sourceType,
      sourceLocalId: cmd.sourceLocalId,
      matchedAmountPaise: cmd.matchedAmountPaise,
    );
  }

  @override
  Future<ReconciliationEntity> finalizeReconciliation(
    FinalizeReconciliationCommand cmd,
  ) async {
    final lid = IdGenerator.newId();
    final now = DateTime.now().toUtc();
    // Calculate total of matched lines.
    final matchedTotal = await _db
        .customSelect(
          'SELECT COALESCE(SUM(matched_amount_paise), 0) AS total FROM bank_matches '
          'WHERE company_id = ?1 AND is_reconciled = 0',
          variables: [Variable(cmd.companyId)],
        )
        .get();
    final total = matchedTotal.first.data['total'] as int? ?? 0;

    if (total != cmd.closingBalancePaise - cmd.openingBalancePaise) {
      throw const ValidationException(
        'Matched total does not equal statement balance difference.',
      );
    }

    await _db
        .into(_db.bankReconciliations)
        .insert(
          BankReconciliationsCompanion(
            localId: Value(lid),
            companyId: Value(cmd.companyId),
            bankAccountId: Value(cmd.bankAccountId),
            statementId: Value(cmd.statementId),
            reconciliationDate: Value(cmd.reconciliationDate),
            openingBalancePaise: Value(cmd.openingBalancePaise),
            closingBalancePaise: Value(cmd.closingBalancePaise),
            statementTotalPaise: Value(total),
            isFinalized: const Value(true),
            createdAt: Value(now),
          ),
        );
    // Mark matches as reconciled.
    await _db.customStatement(
      'UPDATE bank_matches SET is_reconciled = 1 WHERE company_id = ?1',
      [cmd.companyId],
    );
    return ReconciliationEntity(
      localId: lid,
      companyId: cmd.companyId,
      bankAccountId: cmd.bankAccountId,
      statementId: cmd.statementId,
      reconciliationDate: cmd.reconciliationDate,
      isFinalized: true,
    );
  }

  @override
  Stream<List<BankStatementEntity>> watchStatements({
    String? companyId,
  }) async* {
    final q = _db.select(_db.bankStatements)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    if (companyId != null) q.where((s) => s.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows
          .map(
            (r) => BankStatementEntity(
              localId: r.localId,
              companyId: r.companyId,
              bankAccountId: r.bankAccountId,
              statementDate: r.statementDate,
              openingBalance: r.openingBalance,
              closingBalance: r.closingBalance,
            ),
          )
          .toList();
    }
  }

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
      if (e.response?.statusCode == 400 || e.response?.statusCode == 422) {
        throw const PermanentSyncException('Validation error');
      }
      if (e.response?.statusCode != null && e.response!.statusCode! >= 500) {
        throw const RetryableSyncException('Server error.');
      }
      throw RetryableSyncException('Network error.', cause: e);
    }
  }
}

int _amountToMicros(String value) =>
    ((double.tryParse(value) ?? 0) * 10000).round();
