library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';

void main() {
  group('Fixed assets', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
    });

    test('1. create asset record', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.fixedAssets)
          .insert(
            FixedAssetsCompanion(
              localId: const Value('fa-1'),
              companyId: const Value('c-1'),
              name: const Value('Server'),
              category: const Value('IT Equipment'),
              purchaseCostPaise: const Value(50000000),
              purchaseDate: const Value('2026-01-15'),
              salvageValuePaise: const Value(5000000),
              usefulLifeMonths: const Value(60),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final assets = await db.select(db.fixedAssets).get();
      expect(assets.length, 1);
      expect(assets.first.name, 'Server');
    });

    test('2. company isolation', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.fixedAssets)
          .insert(
            FixedAssetsCompanion(
              localId: const Value('fa-c1'),
              companyId: const Value('c-1'),
              name: const Value('Asset1'),
              category: const Value('Cat1'),
              purchaseCostPaise: const Value(100000),
              purchaseDate: const Value('2026-01-01'),
              usefulLifeMonths: const Value(12),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.fixedAssets)
          .insert(
            FixedAssetsCompanion(
              localId: const Value('fa-c2'),
              companyId: const Value('c-2'),
              name: const Value('Asset2'),
              category: const Value('Cat2'),
              purchaseCostPaise: const Value(200000),
              purchaseDate: const Value('2026-01-01'),
              usefulLifeMonths: const Value(12),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      expect(
        await (db.select(
          db.fixedAssets,
        )..where((a) => a.companyId.equals('c-1'))).get(),
        hasLength(1),
      );
      expect(
        await (db.select(
          db.fixedAssets,
        )..where((a) => a.companyId.equals('c-2'))).get(),
        hasLength(1),
      );
    });

    test('3. rollback: asset creation failure', () async {
      try {
        await db.transaction(() async {
          await db
              .into(db.fixedAssets)
              .insert(
                FixedAssetsCompanion(
                  localId: const Value('fa-rb'),
                  companyId: const Value('c-1'),
                  name: const Value('FailAsset'),
                  category: const Value('Cat'),
                  purchaseCostPaise: const Value(1000),
                  purchaseDate: const Value('2026-01-01'),
                  usefulLifeMonths: const Value(12),
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
          db.fixedAssets,
        )..where((a) => a.localId.equals('fa-rb'))).get(),
        isEmpty,
      );
    });
  });
}
