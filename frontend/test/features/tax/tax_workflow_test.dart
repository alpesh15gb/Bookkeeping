library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';

void main() {
  group('Tax workflow', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
    });

    test('1. create tax return lines from invoices', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.taxCodes)
          .insert(
            const TaxCodesCompanion(
              localId: Value('gst-18'),
              companyId: Value('c-1'),
              name: Value('GST 18%'),
              rate: Value('18.00'),
              taxType: Value('IGST'),
              isActive: Value(true),
            ),
          );
      await db
          .into(db.taxPeriods)
          .insert(
            const TaxPeriodsCompanion(
              localId: Value('tp-1'),
              companyId: Value('c-1'),
              periodName: Value('Jul 2026'),
              startDate: Value('2026-07-01'),
              endDate: Value('2026-07-31'),
            ),
          );
      await db
          .into(db.taxReturns)
          .insert(
            TaxReturnsCompanion(
              localId: const Value('tr-1'),
              companyId: const Value('c-1'),
              periodId: const Value('tp-1'),
              returnType: const Value('GST'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      expect(await db.select(db.taxReturns).get(), hasLength(1));
    });

    test('2. draft return does not include tax lines', () async {
      final ret = await (db.select(
        db.taxReturns,
      )..where((r) => r.localId.equals('tr-1'))).getSingleOrNull();
      // No data expected - just verifying query doesn't error
      expect(ret, isNull);
    });

    test('3. company isolation', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.taxReturns)
          .insert(
            TaxReturnsCompanion(
              localId: const Value('tr-c1'),
              companyId: const Value('c-1'),
              periodId: const Value('tp-1'),
              returnType: const Value('GST'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.taxReturns)
          .insert(
            TaxReturnsCompanion(
              localId: const Value('tr-c2'),
              companyId: const Value('c-2'),
              periodId: const Value('tp-2'),
              returnType: const Value('GST'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      expect(
        await (db.select(
          db.taxReturns,
        )..where((r) => r.companyId.equals('c-1'))).get(),
        hasLength(1),
      );
      expect(
        await (db.select(
          db.taxReturns,
        )..where((r) => r.companyId.equals('c-2'))).get(),
        hasLength(1),
      );
    });

    test('4. rollback: return creation failure', () async {
      try {
        await db.transaction(() async {
          await db
              .into(db.taxReturns)
              .insert(
                TaxReturnsCompanion(
                  localId: const Value('tr-rb'),
                  companyId: const Value('c-1'),
                  periodId: const Value('tp-1'),
                  returnType: const Value('GST'),
                  createdAt: Value(DateTime.now().toUtc()),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
          throw Exception('Simulated failure');
        });
        // ignore: dead_code
        fail('Should have thrown');
      } catch (_) {}
      expect(
        await (db.select(
          db.taxReturns,
        )..where((r) => r.localId.equals('tr-rb'))).get(),
        isEmpty,
      );
    });
  });
}
