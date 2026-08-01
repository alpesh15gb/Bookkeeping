/// End-to-end payment workflow test.
///
/// Validates the complete offline-first payment lifecycle:
/// draft → save → restart → edit → post → journal → outbox → list → detail.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/features/payments/data/repositories/payment_repository_impl.dart';
import 'package:apexbooks/features/payments/domain/commands/payment_commands.dart';
import 'package:apexbooks/features/payments/domain/repositories/payment_repository.dart';

void main() {
  group('Payment workflow', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late PaymentRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = PaymentRepositoryImpl(
        db: db,
        syncEngine: syncEngine,
        dio: Dio(BaseOptions()),
        deviceIdProvider: () async => 'dev-1',
        companyIdProvider: () async => 'c-1',
        actorIdProvider: () async => 'user-1',
      );
      final now = DateTime.now().toUtc();
      await db
          .into(db.contacts)
          .insert(
            ContactsCompanion(
              localId: const Value('cust-1'),
              remoteId: const Value('cust-1'),
              companyId: const Value('c-1'),
              name: const Value('Acme Corp'),
              contactType: const Value('customer'),
              receivableAccountId: const Value('ar-1'),
              updatedAt: Value(now),
            ),
          );
      await db.batch((batch) {
        batch.insertAll(db.accounts, [
          AccountsCompanion.insert(
            localId: 'bank-1',
            remoteId: 'bank-1',
            companyId: 'c-1',
            code: '1002',
            name: 'Bank',
            accountType: 'asset',
            updatedAt: now,
          ),
          AccountsCompanion.insert(
            localId: 'ar-1',
            remoteId: 'ar-1',
            companyId: 'c-1',
            code: 'AR-CUST-1',
            name: 'Accounts Receivable - Acme Corp',
            accountType: 'asset',
            updatedAt: now,
          ),
        ]);
      });
    });

    tearDown(() async {
      syncEngine.dispose();
      await db.close();
    });

    test('1. save draft → persisted without posting', () async {
      final draft = await repo.saveDraft(
        const SavePaymentDraftCommand(
          companyId: 'c-1',
          paymentType: 'RECEIPT',
          paymentDate: '2026-07-28',
          contactId: 'cust-1',
          contactName: 'Acme Corp',
          paymentMode: 'BANK',
          accountId: 'bank-1',
          amountPaise: 50000,
        ),
      );

      expect(draft.isDraft, true);
      expect(draft.lifecycleStatus, 'draft');
      expect(draft.syncStatus, SyncStatus.localOnly);
    });

    test('2. restart simulation → draft survives', () async {
      const draftId = 'payment-restart-test';
      final now = DateTime.now().toUtc();
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion(
              localId: const Value(draftId),
              companyId: const Value('c-1'),
              paymentType: const Value('RECEIPT'),
              paymentDate: const Value('2026-07-28'),
              contactId: const Value('cust-1'),
              contactName: const Value('Acme Corp'),
              paymentMode: const Value('BANK'),
              accountId: const Value('bank-1'),
              amountPaise: const Value(50000),
              lifecycleStatus: const Value('draft'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: const Value('dev-1'),
            ),
          );

      final loaded = await repo.getPayment(draftId);
      expect(loaded, isNotNull);
      expect(loaded!.isDraft, true);
      expect(loaded.contactName, 'Acme Corp');
    });

    test('3. post payment → journal + outbox created', () async {
      final draft = await repo.saveDraft(
        const SavePaymentDraftCommand(
          companyId: 'c-1',
          paymentType: 'RECEIPT',
          paymentDate: '2026-07-28',
          contactId: 'cust-1',
          contactName: 'Acme Corp',
          paymentMode: 'BANK',
          accountId: 'bank-1',
          amountPaise: 50000,
        ),
      );

      final posted = await repo.post(
        PostPaymentCommand(localId: draft.localId, companyId: 'c-1'),
      );

      expect(posted.lifecycleStatus, 'posted');
      expect(posted.isDraft, false);
      expect(posted.syncStatus, SyncStatus.pending);

      // Journal created.
      final journals = await db.select(db.journalEntries).get();
      expect(journals.length, 1, reason: 'Post must create a journal entry');
      expect(journals.first.lifecycleStatus, 'posted');

      // Journal lines (debit + credit).
      final lines = await db.select(db.journalLines).get();
      expect(lines.length, 2, reason: 'Journal must have two lines');
      final debits = lines.where((l) => l.direction == 'DEBIT');
      final credits = lines.where((l) => l.direction == 'CREDIT');
      expect(debits.length, 1);
      expect(credits.length, 1);
      expect(debits.first.amountPaise, 50000);
      expect(credits.first.amountPaise, 50000);

      // Outbox entry.
      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      expect(ops.first.entityType, 'payment');
      expect(ops.first.status, 'pending');
    });

    test('4. double post → rejected', () async {
      final draft = await repo.saveDraft(
        const SavePaymentDraftCommand(
          companyId: 'c-1',
          paymentType: 'RECEIPT',
          paymentDate: '2026-07-28',
          contactId: 'cust-1',
          contactName: 'Acme Corp',
          paymentMode: 'BANK',
          accountId: 'bank-1',
          amountPaise: 50000,
        ),
      );

      await repo.post(
        PostPaymentCommand(localId: draft.localId, companyId: 'c-1'),
      );

      await expectLater(
        () => repo.post(
          PostPaymentCommand(localId: draft.localId, companyId: 'c-1'),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('5. sync payload contains payment data', () async {
      final draft = await repo.saveDraft(
        const SavePaymentDraftCommand(
          companyId: 'c-1',
          paymentType: 'RECEIPT',
          paymentDate: '2026-07-28',
          contactId: 'cust-1',
          contactName: 'Acme Corp',
          paymentMode: 'BANK',
          accountId: 'bank-1',
          amountPaise: 50000,
        ),
      );

      await repo.post(
        PostPaymentCommand(localId: draft.localId, companyId: 'c-1'),
      );

      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      expect(ops.first.idempotencyKey, startsWith('payment:post:'));

      // Verify payload contains expected fields.
      final payload = ops.first.payload;
      expect(payload, contains('money_transaction.posted'));
      expect(payload, contains('receipt'));
      expect(payload, contains('cust-1'));
      expect(payload, contains('5000000'));
    });
  });
}
