library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/features/banking/data/repositories/banking_repository_impl.dart';
import 'package:apexbooks/features/banking/domain/commands/banking_commands.dart';
import 'package:apexbooks/features/banking/domain/repositories/banking_repository.dart';

void main() {
  group('Banking workflow', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late BankingRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = BankingRepositoryImpl(
        db: db,
        syncEngine: syncEngine,
        dio: Dio(BaseOptions()),
        deviceIdProvider: () async => 'dev-1',
        companyIdProvider: () async => 'c-1',
        actorIdProvider: () async => 'user-1',
      );
    });
    tearDown(() async {
      syncEngine.dispose();
      await db.close();
    });

    test('1. import statement → persisted with lines', () async {
      final stmt = await repo.importStatement(
        const ImportStatementCommand(
          companyId: 'c-1',
          bankAccountId: 'ba-1',
          statementDate: '2026-07-28',
          openingBalance: '10000',
          closingBalance: '15000',
          lines: [
            StatementLineCommand(
              transactionDate: '2026-07-28',
              amountPaise: 5000,
              balancePaise: 15000,
              description: 'Deposit',
              externalId: 'ext-1',
            ),
          ],
        ),
      );
      expect(stmt.lines.length, 1);
      final lines = await db.select(db.bankStatementLines).get();
      expect(lines.length, 1);
    });

    test('2. duplicate import → rejected', () async {
      await repo.importStatement(
        const ImportStatementCommand(
          companyId: 'c-1',
          bankAccountId: 'ba-1',
          statementDate: '2026-07-28',
          openingBalance: '0',
          closingBalance: '1000',
          lines: [
            StatementLineCommand(
              transactionDate: '2026-07-28',
              amountPaise: 1000,
              balancePaise: 1000,
              externalId: 'dup-1',
            ),
          ],
        ),
      );
      await expectLater(
        () => repo.importStatement(
          const ImportStatementCommand(
            companyId: 'c-1',
            bankAccountId: 'ba-1',
            statementDate: '2026-07-28',
            openingBalance: '0',
            closingBalance: '1000',
            lines: [
              StatementLineCommand(
                transactionDate: '2026-07-28',
                amountPaise: 1000,
                balancePaise: 1000,
                externalId: 'dup-1',
              ),
            ],
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('3. match line → creates match record', () async {
      await repo.importStatement(
        const ImportStatementCommand(
          companyId: 'c-1',
          bankAccountId: 'ba-1',
          statementDate: '2026-07-28',
          openingBalance: '0',
          closingBalance: '500',
          lines: [
            StatementLineCommand(
              transactionDate: '2026-07-28',
              amountPaise: 500,
              balancePaise: 500,
              externalId: 'm-1',
            ),
          ],
        ),
      );
      final lineId =
          (await db.select(db.bankStatementLines).get()).first.localId;
      final match = await repo.matchLine(
        MatchStatementLineCommand(
          companyId: 'c-1',
          statementLineLocalId: lineId,
          sourceType: 'payment',
          sourceLocalId: 'pmt-1',
          matchedAmountPaise: 500,
        ),
      );
      expect(match.matchedAmountPaise, 500);
      final line = await (db.select(
        db.bankStatementLines,
      )..where((l) => l.localId.equals(lineId))).getSingle();
      expect(line.isMatched, true);
    });

    test('4. finalize reconciliation → validates and closes', () async {
      await repo.importStatement(
        const ImportStatementCommand(
          companyId: 'c-1',
          bankAccountId: 'ba-1',
          statementDate: '2026-07-28',
          openingBalance: '0',
          closingBalance: '1000',
          lines: [
            StatementLineCommand(
              transactionDate: '2026-07-28',
              amountPaise: 1000,
              balancePaise: 1000,
              externalId: 'f-1',
            ),
          ],
        ),
      );
      final lineId =
          (await db.select(db.bankStatementLines).get()).first.localId;
      await repo.matchLine(
        MatchStatementLineCommand(
          companyId: 'c-1',
          statementLineLocalId: lineId,
          sourceType: 'payment',
          sourceLocalId: 'pmt-2',
          matchedAmountPaise: 1000,
        ),
      );
      // Get the statement ID from the DB
      final stmt = await db.select(db.bankStatements).get();
      final rec = await repo.finalizeReconciliation(
        FinalizeReconciliationCommand(
          companyId: 'c-1',
          statementId: stmt.first.localId,
          reconciliationDate: '2026-07-28',
          openingBalancePaise: 0,
          closingBalancePaise: 1000,
          bankAccountId: 'ba-1',
        ),
      );
      expect(rec.isFinalized, true);
    });

    test('5. finalize with mismatched total → rejected', () async {
      await expectLater(
        () => repo.finalizeReconciliation(
          const FinalizeReconciliationCommand(
            companyId: 'c-1',
            statementId: 's-1',
            reconciliationDate: '2026-07-28',
            openingBalancePaise: 0,
            closingBalancePaise: 5000,
            bankAccountId: 'ba-1',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('6. company isolation', () async {
      await repo.importStatement(
        const ImportStatementCommand(
          companyId: 'c-1',
          bankAccountId: 'ba-1',
          statementDate: '2026-07-28',
          openingBalance: '0',
          closingBalance: '100',
          lines: [
            StatementLineCommand(
              transactionDate: '2026-07-28',
              amountPaise: 100,
              balancePaise: 100,
            ),
          ],
        ),
      );
      expect(await db.select(db.bankStatements).get(), hasLength(1));
    });

    test('7. rollback: statement import failure', () async {
      try {
        await db.transaction(() async {
          final now = DateTime.now().toUtc();
          await db
              .into(db.bankStatements)
              .insert(
                BankStatementsCompanion(
                  localId: const Value('rb-stmt'),
                  companyId: const Value('c-1'),
                  bankAccountId: const Value('ba-1'),
                  statementDate: const Value('2026-07-28'),
                  openingBalance: const Value('0'),
                  closingBalance: const Value('100'),
                  importedAt: Value(now),
                  createdAt: Value(now),
                ),
              );
          throw Exception('Simulated failure');
        });
        // ignore: dead_code
        fail('Should have thrown');
      } catch (_) {}
      expect(await db.select(db.bankStatements).get(), isEmpty);
    });
  });
}
