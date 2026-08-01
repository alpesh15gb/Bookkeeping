/// End-to-end sales fulfillment workflow test.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/features/sales/data/repositories/sales_repository_impl.dart';
import 'package:apexbooks/features/sales/domain/commands/sales_commands.dart';
import 'package:apexbooks/features/sales/domain/repositories/sales_repository.dart';

void main() {
  group('Sales fulfillment workflow', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late SalesRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = SalesRepositoryImpl(
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

    /// Seed a stock item with given quantity and cost.
    Future<void> seedStock(String name, double qty, int costPaise) async {
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
              unitCostPaise: Value(costPaise),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    }

    test('1. create SO draft → persisted', () async {
      final so = await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 100000,
          lines: [
            SalesOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 1000,
              quantityOrdered: '100',
              totalPaise: 100000,
              sortOrder: 0,
            ),
          ],
        ),
      );
      expect(so.isDraft, true);
      expect(so.lines.length, 1);
    });

    test('2. restart → SO survives', () async {
      final so = await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 50000,
          lines: [
            SalesOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 500,
              quantityOrdered: '100',
              totalPaise: 50000,
              sortOrder: 0,
            ),
          ],
        ),
      );
      final reloaded = await repo.getSalesOrder(so.localId);
      expect(reloaded, isNotNull);
      expect(reloaded!.customerName, 'Client A');
    });

    test(
      '3. partial delivery → stock decreases, COGS journal, order updated',
      () async {
        await seedStock('Widget', 100, 2000); // 100 units at ₹20 cost
        final so = await repo.saveSalesOrderDraft(
          const SaveSalesOrderDraftCommand(
            companyId: 'c-1',
            orderDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            totalPaise: 50000,
            lines: [
              SalesOrderLineCommand(
                productName: 'Widget',
                unit: 'PCS',
                unitPricePaise: 500,
                quantityOrdered: '100',
                totalPaise: 50000,
                sortOrder: 0,
              ),
            ],
          ),
        );

        await repo.deliverGoods(
          DeliverGoodsCommand(
            companyId: 'c-1',
            salesOrderLocalId: so.localId,
            deliveryDate: '2026-07-29',
            customerId: 'cust-1',
            customerName: 'Client A',
            lines: [
              SalesDeliveryLineCommand(
                salesOrderLineLocalId: so.lines.first.localId,
                productName: 'Widget',
                unit: 'PCS',
                quantityDelivered: '30',
                unitPricePaise: 500,
                sortOrder: 0,
              ),
            ],
          ),
        );

        // Stock decreased (100 - 30 = 70).
        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.name.equals('Widget'))).getSingle();
        expect(double.tryParse(stock.currentQuantity)!, closeTo(70, 0.001));
        expect(stock.unitCostPaise, 2000); // cost unchanged

        // COGS journal: DEBIT 60,000 CREDIT 60,000 (30 × 2000)
        final journals = await db.select(db.journalEntries).get();
        expect(journals.length, 1);
        final lines = await db.select(db.journalLines).get();
        expect(lines.length, 2);
        expect(lines.first.direction, 'DEBIT');
        expect(lines.first.amountPaise, 60000);
        expect(lines.first.accountName, 'Cost of Goods Sold');
        expect(lines.last.direction, 'CREDIT');
        expect(lines.last.amountPaise, 60000);

        // Order status = DELIVERING (partial).
        final updatedSo = await repo.getSalesOrder(so.localId);
        expect(updatedSo!.status, 'DELIVERING');
        expect(updatedSo.lines.first.quantityDelivered, '30.000');

        // Outbox created.
        final ops = await db.select(db.syncOperations).get();
        expect(ops.length, 1);
        expect(ops.first.entityType, 'sales_delivery');
        expect(ops.first.status, 'pending');
      },
    );

    test('4. full delivery → order becomes DELIVERED', () async {
      await seedStock('Widget', 50, 1000);
      final so = await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 25000,
          lines: [
            SalesOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 500,
              quantityOrdered: '10',
              totalPaise: 5000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      await repo.deliverGoods(
        DeliverGoodsCommand(
          companyId: 'c-1',
          salesOrderLocalId: so.localId,
          deliveryDate: '2026-07-29',
          customerId: 'cust-1',
          customerName: 'Client A',
          lines: [
            SalesDeliveryLineCommand(
              salesOrderLineLocalId: so.lines.first.localId,
              productName: 'Widget',
              unit: 'PCS',
              quantityDelivered: '10',
              unitPricePaise: 500,
              sortOrder: 0,
            ),
          ],
        ),
      );

      final updatedSo = await repo.getSalesOrder(so.localId);
      expect(updatedSo!.status, 'DELIVERED');
    });

    test('5. insufficient stock → rejected', () async {
      await seedStock('Widget', 5, 1000);
      final so = await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 10000,
          lines: [
            SalesOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 1000,
              quantityOrdered: '10',
              totalPaise: 10000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      await expectLater(
        () => repo.deliverGoods(
          DeliverGoodsCommand(
            companyId: 'c-1',
            salesOrderLocalId: so.localId,
            deliveryDate: '2026-07-29',
            customerId: 'cust-1',
            customerName: 'Client A',
            lines: [
              SalesDeliveryLineCommand(
                salesOrderLineLocalId: so.lines.first.localId,
                productName: 'Widget',
                unit: 'PCS',
                quantityDelivered: '10',
                unitPricePaise: 1000,
                sortOrder: 0,
              ),
            ],
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      '6. cross-domain rollback: failure after stock reduction but before outbox',
      () async {
        await seedStock('RollbackItem', 100, 1000);
        final so = await repo.saveSalesOrderDraft(
          const SaveSalesOrderDraftCommand(
            companyId: 'c-1',
            orderDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client R',
            totalPaise: 10000,
            lines: [
              SalesOrderLineCommand(
                productName: 'RollbackItem',
                unit: 'PCS',
                unitPricePaise: 100,
                quantityOrdered: '50',
                totalPaise: 5000,
                sortOrder: 0,
              ),
            ],
          ),
        );

        try {
          await db.transaction(() async {
            final now = DateTime.now().toUtc();
            await db
                .into(db.salesDeliveries)
                .insert(
                  SalesDeliveriesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    salesOrderLocalId: Value(so.localId),
                    deliveryDate: const Value('2026-07-29'),
                    customerId: const Value('cust-1'),
                    customerName: const Value('Client R'),
                    lifecycleStatus: const Value('posted'),
                    syncStatus: const Value('pending'),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            await (db.update(db.stockItems)
                  ..where((s) => s.name.equals('RollbackItem')))
                .write(const StockItemsCompanion(currentQuantity: Value('50')));
            await db
                .into(db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    stockItemId: Value(IdGenerator.newId()),
                    movementType: const Value('ISSUE'),
                    quantity: const Value('-50'),
                    balanceAfter: const Value('50'),
                    unitCostPaise: const Value(1000),
                    totalPaise: const Value(50000),
                    movementDate: const Value('2026-07-29'),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            await db
                .into(db.journalEntries)
                .insert(
                  JournalEntriesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    entryDate: const Value('2026-07-29'),
                    description: const Value('Rollback test'),
                    sourceType: const Value('AUTO'),
                    lifecycleStatus: const Value('posted'),
                    syncStatus: const Value('localOnly'),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            throw Exception('Simulated outbox failure');
          });
          // ignore: dead_code
          fail('Should have thrown');
        } catch (_) {}

        // Nothing survived.
        expect(await db.select(db.salesDeliveries).get(), isEmpty);
        expect(await db.select(db.salesDeliveryLines).get(), isEmpty);
        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.name.equals('RollbackItem'))).getSingle();
        expect(double.tryParse(stock.currentQuantity)!, closeTo(100, 0.001));
        expect(await db.select(db.inventoryMovements).get(), isEmpty);
        expect(await db.select(db.journalEntries).get(), isEmpty);
        expect(await db.select(db.syncOperations).get(), isEmpty);
      },
    );

    test('7. company isolation', () async {
      await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 10000,
          lines: [],
        ),
      );
      await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-2',
          orderDate: '2026-07-28',
          customerId: 'cust-2',
          customerName: 'Client B',
          totalPaise: 20000,
          lines: [],
        ),
      );

      final c1 = await (db.select(
        db.salesOrders,
      )..where((o) => o.companyId.equals('c-1'))).get();
      expect(c1.length, 1);
      expect(c1.first.customerName, 'Client A');

      final c2 = await (db.select(
        db.salesOrders,
      )..where((o) => o.companyId.equals('c-2'))).get();
      expect(c2.length, 1);
      expect(c2.first.customerName, 'Client B');
    });

    test('8. sync payload contains delivery data', () async {
      await seedStock('Widget', 100, 2000);
      final so = await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 50000,
          lines: [
            SalesOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 500,
              quantityOrdered: '100',
              totalPaise: 50000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      await repo.deliverGoods(
        DeliverGoodsCommand(
          companyId: 'c-1',
          salesOrderLocalId: so.localId,
          deliveryDate: '2026-07-29',
          customerId: 'cust-1',
          customerName: 'Client A',
          lines: [
            SalesDeliveryLineCommand(
              salesOrderLineLocalId: so.lines.first.localId,
              productName: 'Widget',
              unit: 'PCS',
              quantityDelivered: '30',
              unitPricePaise: 500,
              sortOrder: 0,
            ),
          ],
        ),
      );

      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      final payload = ops.first.payload;
      expect(payload, contains('sales_delivery.posted'));
      expect(payload, contains('Widget'));
      expect(payload, contains('30'));
      expect(payload, contains('60000')); // COGS: 30 × 2000
    });

    test(
      '9. create invoice from delivery → number consumed, journal created, outbox',
      () async {
        // Seed allocation.
        await db
            .into(db.numberAllocations)
            .insert(
              NumberAllocationsCompanion(
                id: const Value('alloc-sales-1'),
                allocationId: const Value('alloc-srv-1'),
                companyId: const Value('c-1'),
                deviceId: const Value('dev-1'),
                financialYearId: const Value('fy-2026'),
                series: const Value('SALES'),
                documentType: const Value('INVOICE'),
                fromNum: const Value(5001),
                toNum: const Value(5010),
                used: const Value(0),
                isActive: const Value(true),
                allocatedAt: Value(DateTime.now().toUtc()),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );

        await seedStock('Widget', 100, 2000);
        final so = await repo.saveSalesOrderDraft(
          const SaveSalesOrderDraftCommand(
            companyId: 'c-1',
            orderDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client A',
            totalPaise: 50000,
            lines: [
              SalesOrderLineCommand(
                productName: 'Widget',
                unit: 'PCS',
                unitPricePaise: 500,
                quantityOrdered: '100',
                totalPaise: 50000,
                sortOrder: 0,
              ),
            ],
          ),
        );
        // Deliver all 100.
        await repo.deliverGoods(
          DeliverGoodsCommand(
            companyId: 'c-1',
            salesOrderLocalId: so.localId,
            deliveryDate: '2026-07-29',
            customerId: 'cust-1',
            customerName: 'Client A',
            lines: [
              SalesDeliveryLineCommand(
                salesOrderLineLocalId: so.lines.first.localId,
                productName: 'Widget',
                unit: 'PCS',
                quantityDelivered: '100',
                unitPricePaise: 500,
                sortOrder: 0,
              ),
            ],
          ),
        );
        final deliveryRows = await db.select(db.salesDeliveries).get();
        final deliveryId = deliveryRows.first.localId;

        final updatedSo = await repo.createInvoiceFromDelivery(
          CreateInvoiceFromDeliveryCommand(
            companyId: 'c-1',
            deliveryLocalId: deliveryId,
            invoiceDate: '2026-07-30',
            customerId: 'cust-1',
            customerName: 'Client A',
            deviceId: 'dev-1',
            financialYearId: 'fy-2026',
            series: 'SALES',
            taxPaise: 0,
            totalPaise: 50000,
          ),
        );

        // Order status = INVOICED.
        expect(updatedSo.status, 'INVOICED');

        // Number consumed.
        final alloc = await (db.select(
          db.numberAllocations,
        )..where((a) => a.id.equals('alloc-sales-1'))).getSingle();
        expect(alloc.used, 1);

        // Invoice created.
        final invoices = await db.select(db.invoices).get();
        expect(invoices.length, 1);
        expect(invoices.first.number, 5001);
        expect(invoices.first.lifecycleStatus, 'issued');

        // Journal created (DEBIT AR, CREDIT Revenue).
        final journals = await db.select(db.journalEntries).get();
        // We already have one from the COGS journal, so expect 2 total.
        expect(journals.length, 2);
        final invJournal = journals.last;
        expect(invJournal.description, contains('Invoice #5001'));
        final lines = await db.select(db.journalLines).get();
        // 2 COGS lines + 2 invoice lines = 4
        expect(lines.length, 4);

        // Outbox created (delivery outbox + invoice outbox = 2).
        final ops = await db.select(db.syncOperations).get();
        expect(ops.length, 2);
        expect(ops.last.entityType, 'invoice');
        expect(ops.last.status, 'pending');
      },
    );

    test('10. duplicate invoice-from-delivery → rejected', () async {
      await db
          .into(db.numberAllocations)
          .insert(
            NumberAllocationsCompanion(
              id: const Value('alloc-sales-2'),
              allocationId: const Value('alloc-srv-2'),
              companyId: const Value('c-1'),
              deviceId: const Value('dev-1'),
              financialYearId: const Value('fy-2026'),
              series: const Value('SALES'),
              documentType: const Value('INVOICE'),
              fromNum: const Value(6001),
              toNum: const Value(6010),
              used: const Value(0),
              isActive: const Value(true),
              allocatedAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      await seedStock('Widget', 100, 2000);
      final so = await repo.saveSalesOrderDraft(
        const SaveSalesOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          customerId: 'cust-1',
          customerName: 'Client A',
          totalPaise: 50000,
          lines: [
            SalesOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 500,
              quantityOrdered: '100',
              totalPaise: 50000,
              sortOrder: 0,
            ),
          ],
        ),
      );
      await repo.deliverGoods(
        DeliverGoodsCommand(
          companyId: 'c-1',
          salesOrderLocalId: so.localId,
          deliveryDate: '2026-07-29',
          customerId: 'cust-1',
          customerName: 'Client A',
          lines: [
            SalesDeliveryLineCommand(
              salesOrderLineLocalId: so.lines.first.localId,
              productName: 'Widget',
              unit: 'PCS',
              quantityDelivered: '100',
              unitPricePaise: 500,
              sortOrder: 0,
            ),
          ],
        ),
      );
      final deliveryId =
          (await db.select(db.salesDeliveries).get()).first.localId;

      await repo.createInvoiceFromDelivery(
        CreateInvoiceFromDeliveryCommand(
          companyId: 'c-1',
          deliveryLocalId: deliveryId,
          invoiceDate: '2026-07-30',
          customerId: 'cust-1',
          customerName: 'Client A',
          deviceId: 'dev-1',
          financialYearId: 'fy-2026',
          series: 'SALES',
          taxPaise: 0,
          totalPaise: 50000,
        ),
      );

      // Second invoice from same delivery must fail (all qty already invoiced).
      await expectLater(
        () => repo.createInvoiceFromDelivery(
          CreateInvoiceFromDeliveryCommand(
            companyId: 'c-1',
            deliveryLocalId: deliveryId,
            invoiceDate: '2026-07-30',
            customerId: 'cust-1',
            customerName: 'Client A',
            deviceId: 'dev-1',
            financialYearId: 'fy-2026',
            series: 'SALES',
            taxPaise: 0,
            totalPaise: 50000,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      '11. invoice-from-delivery rollback: failure after number consumption',
      () async {
        await db
            .into(db.numberAllocations)
            .insert(
              NumberAllocationsCompanion(
                id: const Value('alloc-rollback'),
                allocationId: const Value('alloc-rb'),
                companyId: const Value('c-1'),
                deviceId: const Value('dev-1'),
                financialYearId: const Value('fy-2026'),
                series: const Value('SALES'),
                documentType: const Value('INVOICE'),
                fromNum: const Value(7001),
                toNum: const Value(7010),
                used: const Value(0),
                isActive: const Value(true),
                allocatedAt: Value(DateTime.now().toUtc()),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
        await seedStock('RollbackWidget', 50, 1000);
        final so = await repo.saveSalesOrderDraft(
          const SaveSalesOrderDraftCommand(
            companyId: 'c-1',
            orderDate: '2026-07-28',
            customerId: 'cust-1',
            customerName: 'Client R',
            totalPaise: 25000,
            lines: [
              SalesOrderLineCommand(
                productName: 'RollbackWidget',
                unit: 'PCS',
                unitPricePaise: 500,
                quantityOrdered: '50',
                totalPaise: 25000,
                sortOrder: 0,
              ),
            ],
          ),
        );
        await repo.deliverGoods(
          DeliverGoodsCommand(
            companyId: 'c-1',
            salesOrderLocalId: so.localId,
            deliveryDate: '2026-07-29',
            customerId: 'cust-1',
            customerName: 'Client R',
            lines: [
              SalesDeliveryLineCommand(
                salesOrderLineLocalId: so.lines.first.localId,
                productName: 'RollbackWidget',
                unit: 'PCS',
                quantityDelivered: '50',
                unitPricePaise: 500,
                sortOrder: 0,
              ),
            ],
          ),
        );
        // Simulate failure after invoice creation + number consumption but before outbox.
        try {
          await db.transaction(() async {
            final now = DateTime.now().toUtc();
            await (db.update(db.numberAllocations)
                  ..where((a) => a.id.equals('alloc-rollback')))
                .write(const NumberAllocationsCompanion(used: Value(1)));
            await db
                .into(db.invoices)
                .insert(
                  InvoicesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    number: const Value(7001),
                    allocationId: const Value('alloc-rb'),
                    invoiceDate: const Value('2026-07-30'),
                    customerId: const Value('cust-1'),
                    customerName: const Value('Client R'),
                    totalPaise: const Value(25000),
                    lifecycleStatus: const Value('issued'),
                    syncStatus: const Value('pending'),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            await db
                .into(db.journalEntries)
                .insert(
                  JournalEntriesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    entryDate: const Value('2026-07-30'),
                    description: const Value('Rollback invoice'),
                    sourceType: const Value('AUTO'),
                    lifecycleStatus: const Value('posted'),
                    syncStatus: const Value('localOnly'),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            throw Exception('Simulated outbox failure after invoice creation');
          });
          // ignore: dead_code
          fail('Should have thrown');
        } catch (_) {}

        // Verify the invoice-specific data was rolled back.
        expect(
          await db.select(db.invoices).get(),
          isEmpty,
          reason: 'Invoice must be rolled back',
        );

        // Allocation must be rolled back.
        final allocRow = await (db.select(
          db.numberAllocations,
        )..where((a) => a.id.equals('alloc-rollback'))).getSingle();
        expect(allocRow.used, 0, reason: 'Allocation must be rolled back');

        // Journal count must be 1 (the COGS journal from delivery, not the invoice journal).
        final journalCount = await db.select(db.journalEntries).get();
        expect(
          journalCount.length,
          1,
          reason:
              'Only the COGS journal should remain (invoice journal must be rolled back)',
        );
      },
    );
  });
}
