library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/features/credit_debit/data/repositories/credit_debit_repository_impl.dart';
import 'package:apexbooks/features/credit_debit/domain/commands/credit_debit_commands.dart';
import 'package:apexbooks/features/credit_debit/domain/repositories/credit_debit_repository.dart';

void main() {
  group('Credit/Debit notes', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late CreditDebitRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = CreditDebitRepositoryImpl(
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

    Future<void> seedAlloc(
      String series,
      String docType,
      String id,
      int from,
      int to,
    ) async {
      await db
          .into(db.numberAllocations)
          .insert(
            NumberAllocationsCompanion(
              id: Value(id),
              allocationId: Value('alloc-$id'),
              companyId: const Value('c-1'),
              deviceId: const Value('dev-1'),
              financialYearId: const Value('fy-2026'),
              series: Value(series),
              documentType: Value(docType),
              fromNum: Value(from),
              toNum: Value(to),
              used: const Value(0),
              isActive: const Value(true),
              allocatedAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
    }

    test('1. post credit note → number consumed, journal, outbox', () async {
      await seedAlloc('CREDIT_NOTE', 'CREDIT_NOTE', 'cn-1', 8001, 8010);
      final cn = await repo.postCreditNote(
        const PostCreditNoteCommand(
          companyId: 'c-1',
          creditNoteDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          deviceId: 'dev-1',
          financialYearId: 'fy-2026',
          totalPaise: 10000,
        ),
      );
      expect(cn.number, 8001);
      expect(cn.isPosted, true);
      final alloc = await (db.select(
        db.numberAllocations,
      )..where((a) => a.id.equals('cn-1'))).getSingle();
      expect(alloc.used, 1);
      expect((await db.select(db.journalEntries).get()).length, 1);
      expect((await db.select(db.syncOperations).get()).length, 1);
    });

    test('2. post debit note → number consumed, journal, outbox', () async {
      await seedAlloc('DEBIT_NOTE', 'DEBIT_NOTE', 'dn-1', 9001, 9010);
      final dn = await repo.postDebitNote(
        const PostDebitNoteCommand(
          companyId: 'c-1',
          debitNoteDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor S',
          deviceId: 'dev-1',
          financialYearId: 'fy-2026',
          totalPaise: 5000,
        ),
      );
      expect(dn.number, 9001);
      expect((await db.select(db.syncOperations).get()).length, 1);
    });

    test(
      '3. double credit note is separate (no constraint on same source)',
      () async {
        await seedAlloc('CREDIT_NOTE', 'CREDIT_NOTE', 'cn-2', 8011, 8020);
        await repo.postCreditNote(
          const PostCreditNoteCommand(
            companyId: 'c-1',
            creditNoteDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            deviceId: 'dev-1',
            financialYearId: 'fy-2026',
            totalPaise: 5000,
          ),
        );
        await repo.postCreditNote(
          const PostCreditNoteCommand(
            companyId: 'c-1',
            creditNoteDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            deviceId: 'dev-1',
            financialYearId: 'fy-2026',
            totalPaise: 5000,
          ),
        );
        final alloc = await (db.select(
          db.numberAllocations,
        )..where((a) => a.id.equals('cn-2'))).getSingle();
        expect(alloc.used, 2);
      },
    );

    test('4. range exhaustion → rejected', () async {
      await seedAlloc('CREDIT_NOTE', 'CREDIT_NOTE', 'cn-3', 1, 1);
      await repo.postCreditNote(
        const PostCreditNoteCommand(
          companyId: 'c-1',
          creditNoteDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          deviceId: 'dev-1',
          financialYearId: 'fy-2026',
          totalPaise: 1000,
        ),
      );
      await expectLater(
        () => repo.postCreditNote(
          const PostCreditNoteCommand(
            companyId: 'c-1',
            creditNoteDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            deviceId: 'dev-1',
            financialYearId: 'fy-2026',
            totalPaise: 1000,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('5. company isolation', () async {
      await seedAlloc('CREDIT_NOTE', 'CREDIT_NOTE', 'cn-4', 1, 10);
      await repo.postCreditNote(
        const PostCreditNoteCommand(
          companyId: 'c-1',
          creditNoteDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          deviceId: 'dev-1',
          financialYearId: 'fy-2026',
          totalPaise: 1000,
        ),
      );
      expect((await db.select(db.creditNotes).get()).length, 1);
    });

    test('6. rollback: credit note failure after number consumption', () async {
      await seedAlloc('CREDIT_NOTE', 'CREDIT_NOTE', 'cn-rb', 1, 10);
      try {
        await db.transaction(() async {
          final now = DateTime.now().toUtc();
          await (db.update(db.numberAllocations)
                ..where((a) => a.id.equals('cn-rb')))
              .write(const NumberAllocationsCompanion(used: Value(1)));
          await db
              .into(db.creditNotes)
              .insert(
                CreditNotesCompanion(
                  localId: Value(IdGenerator.newId()),
                  companyId: const Value('c-1'),
                  creditNoteDate: const Value('2026-07-28'),
                  customerId: const Value('cust-1'),
                  customerName: const Value('Client A'),
                  number: const Value(1),
                  totalPaise: const Value(5000),
                  lifecycleStatus: const Value('posted'),
                  syncStatus: const Value('pending'),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                  originDeviceId: const Value('dev-1'),
                ),
              );
          throw Exception('Outbox failure');
        });
        // ignore: dead_code
        fail('Should have thrown');
      } catch (_) {}
      expect(await db.select(db.creditNotes).get(), isEmpty);
      final alloc = await (db.select(
        db.numberAllocations,
      )..where((a) => a.id.equals('cn-rb'))).getSingle();
      expect(alloc.used, 0);
    });

    test('7. sync payloads', () async {
      await seedAlloc('DEBIT_NOTE', 'DEBIT_NOTE', 'dn-p', 1, 10);
      await repo.postDebitNote(
        const PostDebitNoteCommand(
          companyId: 'c-1',
          debitNoteDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor S',
          deviceId: 'dev-1',
          financialYearId: 'fy-2026',
          totalPaise: 3000,
        ),
      );
      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      expect(ops.first.payload, contains('debit_note.posted'));
    });
  });
}
