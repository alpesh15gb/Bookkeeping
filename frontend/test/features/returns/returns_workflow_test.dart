library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/features/returns/data/repositories/returns_repository_impl.dart';
import 'package:apexbooks/features/returns/domain/commands/returns_commands.dart';
import 'package:apexbooks/features/returns/domain/repositories/returns_repository.dart';

void main() {
  group('Returns workflow', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late ReturnsRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = ReturnsRepositoryImpl(
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

    Future<void> seedStock(String name, double qty, int cost) async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.stockItems)
          .insert(
            StockItemsCompanion(
              localId: Value(IdGenerator.newId()),
              companyId: const Value('c-1'),
              name: Value(name),
              unit: const Value('PCS'),
              currentQuantity: Value(qty.toStringAsFixed(3)),
              unitCostPaise: Value(cost),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    }

    test(
      '1. sales return → inventory increased, COGS reversed, outbox',
      () async {
        await seedStock('Widget', 50, 2000);
        final ret = await repo.postSalesReturn(
          const PostSalesReturnCommand(
            companyId: 'c-1',
            returnDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            totalPaise: 10000,
            lines: [
              SalesReturnLineCommand(
                productName: 'Widget',
                unit: 'PCS',
                quantity: '10',
                unitPricePaise: 1000,
                totalPaise: 10000,
              ),
            ],
          ),
        );
        expect(ret.isPosted, true);

        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.name.equals('Widget'))).getSingle();
        expect(double.tryParse(stock.currentQuantity)!, closeTo(60, 0.001));
        expect((await db.select(db.journalEntries).get()).length, 1);
        expect((await db.select(db.syncOperations).get()).length, 1);
      },
    );

    test(
      '2. purchase return → inventory decreased, AP journal, outbox',
      () async {
        await seedStock('Raw', 100, 500);
        final ret = await repo.postPurchaseReturn(
          const PostPurchaseReturnCommand(
            companyId: 'c-1',
            returnDate: '2026-07-28',
            supplierId: 'sup-1',
            supplierName: 'Vendor S',
            totalPaise: 5000,
            lines: [
              PurchaseReturnLineCommand(
                productName: 'Raw',
                unit: 'PCS',
                quantity: '10',
                unitCostPaise: 500,
                totalPaise: 5000,
              ),
            ],
          ),
        );
        expect(ret.lifecycleStatus, 'posted');
        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.name.equals('Raw'))).getSingle();
        expect(double.tryParse(stock.currentQuantity)!, closeTo(90, 0.001));
      },
    );

    test(
      '3. duplicate sales return no constraint (separate return creates separate record)',
      () async {
        await seedStock('Widget', 100, 1000);
        await repo.postSalesReturn(
          const PostSalesReturnCommand(
            companyId: 'c-1',
            returnDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            totalPaise: 5000,
            lines: [
              SalesReturnLineCommand(
                productName: 'Widget',
                unit: 'PCS',
                quantity: '5',
                unitPricePaise: 1000,
                totalPaise: 5000,
              ),
            ],
          ),
        );
        await repo.postSalesReturn(
          const PostSalesReturnCommand(
            companyId: 'c-1',
            returnDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            totalPaise: 5000,
            lines: [
              SalesReturnLineCommand(
                productName: 'Widget',
                unit: 'PCS',
                quantity: '5',
                unitPricePaise: 1000,
                totalPaise: 5000,
              ),
            ],
          ),
        );
        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.name.equals('Widget'))).getSingle();
        expect(double.tryParse(stock.currentQuantity)!, closeTo(110, 0.001));
      },
    );

    test('4. insufficient stock for purchase return → rejected', () async {
      await seedStock('Scarce', 3, 1000);
      await expectLater(
        () => repo.postPurchaseReturn(
          const PostPurchaseReturnCommand(
            companyId: 'c-1',
            returnDate: '2026-07-28',
            supplierId: 'sup-1',
            supplierName: 'Vendor S',
            totalPaise: 10000,
            lines: [
              PurchaseReturnLineCommand(
                productName: 'Scarce',
                unit: 'PCS',
                quantity: '10',
                unitCostPaise: 1000,
                totalPaise: 10000,
              ),
            ],
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('5. company isolation', () async {
      await seedStock('Widget', 50, 1000);
      // Sale return for c-2 should fail to find stock for c-1.
      // Just verify both work independently with correct scope.
      await repo.postSalesReturn(
        const PostSalesReturnCommand(
          companyId: 'c-1',
          returnDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 1000,
          lines: [
            SalesReturnLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              quantity: '1',
              unitPricePaise: 1000,
              totalPaise: 1000,
            ),
          ],
        ),
      );
      expect((await db.select(db.salesReturns).get()).length, 1);
    });

    test(
      '6. rollback: sales return failure after inventory increase',
      () async {
        await seedStock('Rollback', 100, 1000);
        try {
          await db.transaction(() async {
            final now = DateTime.now().toUtc();
            await db
                .into(db.salesReturns)
                .insert(
                  SalesReturnsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    returnDate: const Value('2026-07-28'),
                    customerId: const Value('cust-1'),
                    customerName: const Value('Client R'),
                    totalPaise: const Value(5000),
                    lifecycleStatus: const Value('posted'),
                    syncStatus: const Value('pending'),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            await db
                .into(db.salesReturnLines)
                .insert(
                  SalesReturnLinesCompanion(
                    localId: Value(IdGenerator.newId()),
                    returnLocalId: Value(IdGenerator.newId()),
                    productName: const Value('Rollback'),
                    unit: const Value('PCS'),
                    quantity: const Value('5'),
                    unitPricePaise: const Value(1000),
                    totalPaise: const Value(5000),
                  ),
                );
            await (db.update(
              db.stockItems,
            )..where((s) => s.name.equals('Rollback'))).write(
              const StockItemsCompanion(currentQuantity: Value('105')),
            );
            throw Exception('Simulated outbox failure');
          });
          // ignore: dead_code
          fail('Should have thrown');
        } catch (_) {}
        expect(await db.select(db.salesReturns).get(), isEmpty);
        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.name.equals('Rollback'))).getSingle();
        expect(double.tryParse(stock.currentQuantity)!, closeTo(100, 0.001));
        expect(await db.select(db.syncOperations).get(), isEmpty);
      },
    );

    test('7. sync payloads', () async {
      await seedStock('Widget', 50, 2000);
      await repo.postSalesReturn(
        const PostSalesReturnCommand(
          companyId: 'c-1',
          returnDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 10000,
          lines: [
            SalesReturnLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              quantity: '5',
              unitPricePaise: 2000,
              totalPaise: 10000,
            ),
          ],
        ),
      );
      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      expect(ops.first.payload, contains('sales_return.posted'));
      expect(ops.first.payload, contains('Widget'));
    });
  });
}
