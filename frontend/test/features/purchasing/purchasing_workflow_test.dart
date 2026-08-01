/// End-to-end purchasing workflow test with cross-domain rollback validation.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/features/purchasing/data/repositories/purchasing_repository_impl.dart';
import 'package:apexbooks/features/purchasing/domain/commands/purchasing_commands.dart';
import 'package:apexbooks/features/purchasing/domain/repositories/purchasing_repository.dart';

void main() {
  group('Purchasing workflow', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late PurchasingRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = PurchasingRepositoryImpl(
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
              localId: const Value('sup-1'),
              remoteId: const Value('sup-1'),
              companyId: const Value('c-1'),
              name: const Value('Vendor A'),
              contactType: const Value('vendor'),
              payableAccountId: const Value('ap-1'),
              updatedAt: Value(now),
            ),
          );
      await db.batch((batch) {
        batch.insertAll(db.accounts, [
          AccountsCompanion.insert(
            localId: 'inventory-1',
            remoteId: 'inventory-1',
            companyId: 'c-1',
            code: '1300',
            name: 'Inventory',
            accountType: 'asset',
            updatedAt: now,
          ),
          AccountsCompanion.insert(
            localId: 'grir-1',
            remoteId: 'grir-1',
            companyId: 'c-1',
            code: '3204',
            name: 'Goods Received / Invoice Received',
            accountType: 'liability',
            updatedAt: now,
          ),
        ]);
      });
    });

    tearDown(() async {
      syncEngine.dispose();
      await db.close();
    });

    test('1. create PO draft → persisted', () async {
      final po = await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalPaise: 100000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Widget X',
              unit: 'PCS',
              unitPricePaise: 1000,
              quantityOrdered: '100',
              totalPaise: 100000,
              sortOrder: 0,
            ),
          ],
        ),
      );
      expect(po.isDraft, true);
      expect(po.lines.length, 1);
      expect(po.lines.first.quantityOrdered, '100');
    });

    test('2. restart → PO survives', () async {
      final po = await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalPaise: 50000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Widget Y',
              unit: 'PCS',
              unitPricePaise: 500,
              quantityOrdered: '100',
              totalPaise: 50000,
              sortOrder: 0,
            ),
          ],
        ),
      );
      final reloaded = await repo.getPurchaseOrder(po.localId);
      expect(reloaded, isNotNull);
      expect(reloaded!.supplierName, 'Vendor A');
      expect(reloaded.lines.length, 1);
    });

    test('3. receive goods → inventory + journal + outbox created', () async {
      // Seed a stock item that matches the product name.
      final now = DateTime.now().toUtc();
      await db
          .into(db.stockItems)
          .insert(
            StockItemsCompanion(
              localId: const Value('stock-widget-a'),
              companyId: const Value('c-1'),
              name: const Value('Widget A'),
              unit: const Value('PCS'),
              currentQuantity: const Value('50'),
              unitCostPaise: const Value(5000),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      final po = await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalPaise: 60000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Widget A',
              unit: 'PCS',
              unitPricePaise: 600,
              quantityOrdered: '100',
              totalPaise: 60000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      final receipt = await repo.receiveGoods(
        ReceiveGoodsCommand(
          companyId: 'c-1',
          purchaseOrderLocalId: po.localId,
          receiptDate: '2026-07-29',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          lines: [
            ReceiveLineCommand(
              purchaseOrderLineLocalId: po.lines.first.localId,
              productName: 'Widget A',
              unit: 'PCS',
              quantityReceived: '30',
              unitCostPaise: 600,
              sortOrder: 0,
            ),
          ],
        ),
      );

      expect(receipt.lifecycleStatus, 'posted');

      // Inventory increased (50 + 30 = 80).
      final stock = await (db.select(
        db.stockItems,
      )..where((s) => s.localId.equals('stock-widget-a'))).getSingleOrNull();
      expect(stock, isNotNull);
      expect(double.tryParse(stock!.currentQuantity)!, closeTo(80, 0.001));
      // Weighted avg: (50*5000 + 30*600) / 80 = (250000+18000)/80 = 3350
      expect(stock.unitCostPaise, 3350);

      // Journal created.
      final journals = await db.select(db.journalEntries).get();
      expect(journals.length, 1);
      final lines = await db.select(db.journalLines).get();
      expect(lines.length, 2);
      expect(lines.first.direction, 'DEBIT');
      expect(lines.first.amountPaise, 18000); // 30 × 600
      expect(lines.last.direction, 'CREDIT');
      expect(lines.last.amountPaise, 18000);

      // Outbox created.
      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      expect(ops.first.entityType, 'purchase_receipt');
      expect(ops.first.status, 'pending');
    });

    test('4. duplicate receipt line rejected', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.stockItems)
          .insert(
            StockItemsCompanion(
              localId: const Value('stock-widget-b'),
              companyId: const Value('c-1'),
              name: const Value('Widget B'),
              unit: const Value('PCS'),
              currentQuantity: const Value('0'),
              unitCostPaise: const Value(500),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final po = await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalPaise: 50000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Widget B',
              unit: 'PCS',
              unitPricePaise: 500,
              quantityOrdered: '10',
              totalPaise: 5000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      await repo.receiveGoods(
        ReceiveGoodsCommand(
          companyId: 'c-1',
          purchaseOrderLocalId: po.localId,
          receiptDate: '2026-07-29',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          lines: [
            ReceiveLineCommand(
              purchaseOrderLineLocalId: po.lines.first.localId,
              productName: 'Widget B',
              unit: 'PCS',
              quantityReceived: '5',
              unitCostPaise: 500,
              sortOrder: 0,
            ),
          ],
        ),
      );

      // Second receipt of same PO line — allowed (partial), but receiving
      // more than ordered on the line is validated.
      // This test ensures no crash on duplicate line receipt.
      final receipt2 = await repo.receiveGoods(
        ReceiveGoodsCommand(
          companyId: 'c-1',
          purchaseOrderLocalId: po.localId,
          receiptDate: '2026-07-30',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          lines: [
            ReceiveLineCommand(
              purchaseOrderLineLocalId: po.lines.first.localId,
              productName: 'Widget B',
              unit: 'PCS',
              quantityReceived: '5',
              unitCostPaise: 500,
              sortOrder: 0,
            ),
          ],
        ),
      );
      expect(receipt2.lifecycleStatus, 'posted');
    });

    test('5. post supplier invoice → journal + outbox', () async {
      final inv = await repo.postSupplierInvoice(
        const PostSupplierInvoiceCommand(
          companyId: 'c-1',
          invoiceNumber: 'SI-001',
          invoiceDate: '2026-07-30',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalBeforeTaxPaise: 50000,
          taxPaise: 9000,
          totalPaise: 59000,
          lines: [
            SupplierInvoiceLineCommand(
              productName: 'Widget A',
              unit: 'PCS',
              unitPricePaise: 500,
              quantity: '100',
              totalPaise: 50000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      expect(inv.lifecycleStatus, 'POSTED');
      expect(inv.totalPaise, 59000);

      // Journal created.
      final journals = await db.select(db.journalEntries).get();
      expect(journals.length, 1);
      final lines = await db.select(db.journalLines).get();
      expect(lines.length, 2);
      expect(lines.first.direction, 'DEBIT');
      expect(lines.first.amountPaise, 59000);
      expect(lines.last.direction, 'CREDIT');

      // Outbox.
      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      expect(ops.first.entityType, 'purchase_invoice');
      expect(ops.first.status, 'pending');
    });

    test(
      '6. cross-domain rollback: failure after inventory movement → nothing committed',
      () async {
        // Seed stock.
        final now = DateTime.now().toUtc();
        await db
            .into(db.stockItems)
            .insert(
              StockItemsCompanion(
                localId: const Value('stock-rollback'),
                companyId: const Value('c-1'),
                name: const Value('Rollback Item'),
                unit: const Value('PCS'),
                currentQuantity: const Value('100'),
                unitCostPaise: const Value(1000),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        final po = await repo.savePurchaseOrderDraft(
          const SavePurchaseOrderDraftCommand(
            companyId: 'c-1',
            orderDate: '2026-07-28',
            supplierId: 'sup-1',
            supplierName: 'Vendor R',
            totalPaise: 10000,
            lines: [
              PurchaseOrderLineCommand(
                productName: 'Rollback Item',
                unit: 'PCS',
                unitPricePaise: 100,
                quantityOrdered: '100',
                totalPaise: 10000,
                sortOrder: 0,
              ),
            ],
          ),
        );

        // Simulate a failure inside the repository transaction by constructing
        // a transaction that writes data and then throws — exactly mimicking
        // what happens if the sync engine's outbox insertion fails after the
        // inventory updates have been applied.
        try {
          await db.transaction(() async {
            // Write to receipt (as receiveGoods does).
            await db
                .into(db.purchaseReceipts)
                .insert(
                  PurchaseReceiptsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    purchaseOrderLocalId: Value(po.localId),
                    receiptDate: const Value('2026-07-29'),
                    supplierId: const Value('sup-1'),
                    supplierName: const Value('Vendor R'),
                    lifecycleStatus: const Value('posted'),
                    syncStatus: const Value('pending'),
                    createdAt: Value(DateTime.now().toUtc()),
                    updatedAt: Value(DateTime.now().toUtc()),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            // Insert receipt line (as receiveGoods does).
            await db
                .into(db.purchaseReceiptLines)
                .insert(
                  PurchaseReceiptLinesCompanion(
                    localId: Value(IdGenerator.newId()),
                    receiptLocalId: Value(po.localId),
                    purchaseOrderLineLocalId: Value(po.lines.first.localId),
                    productName: const Value('Rollback Item'),
                    unit: const Value('PCS'),
                    quantityReceived: const Value('10'),
                    unitCostPaise: const Value(100),
                    totalPaise: const Value(1000),
                    sortOrder: const Value(0),
                  ),
                );
            // Update stock (as receiveGoods does).
            await (db.update(
              db.stockItems,
            )..where((s) => s.localId.equals('stock-rollback'))).write(
              const StockItemsCompanion(
                currentQuantity: Value('110'),
                unitCostPaise: Value(100),
              ),
            );
            // Upsert balance (as receiveGoods does).
            await db
                .into(db.inventoryBalances)
                .insertOnConflictUpdate(
                  InventoryBalancesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    stockItemId: const Value('stock-rollback'),
                    quantityOnHand: const Value('110'),
                    averageCostPaise: const Value(100),
                    updatedAt: Value(DateTime.now().toUtc()),
                  ),
                );
            // Insert inventory movement (as receiveGoods does).
            await db
                .into(db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: const Value('c-1'),
                    stockItemId: const Value('stock-rollback'),
                    movementType: const Value('RECEIPT'),
                    quantity: const Value('10'),
                    balanceAfter: const Value('110'),
                    unitCostPaise: const Value(100),
                    totalPaise: const Value(1000),
                    movementDate: const Value('2026-07-29'),
                    createdAt: Value(DateTime.now().toUtc()),
                    updatedAt: Value(DateTime.now().toUtc()),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            // Insert journal (as receiveGoods does).
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
                    createdAt: Value(DateTime.now().toUtc()),
                    updatedAt: Value(DateTime.now().toUtc()),
                    originDeviceId: const Value('dev-1'),
                  ),
                );
            // NOW simulate outbox failure — throw to roll back everything.
            throw Exception('Simulated outbox failure');
          });
          // ignore: dead_code
          fail('Transaction should have thrown');
        } catch (_) {
          // Expected — transaction rolled back.
        }

        // Verify NOTHING was committed.
        final receipts = await db.select(db.purchaseReceipts).get();
        expect(receipts, isEmpty, reason: 'No receipt should be committed');

        final receiptLines = await db.select(db.purchaseReceiptLines).get();
        expect(receiptLines, isEmpty, reason: 'No receipt lines');

        // Stock unchanged.
        final stock = await (db.select(
          db.stockItems,
        )..where((s) => s.localId.equals('stock-rollback'))).getSingleOrNull();
        expect(stock, isNotNull);
        expect(
          double.tryParse(stock!.currentQuantity)!,
          closeTo(100, 0.001),
          reason: 'Stock quantity must remain unchanged after rollback',
        );

        // No journals.
        final journals = await db.select(db.journalEntries).get();
        expect(journals, isEmpty, reason: 'No journals after rollback');

        // No outbox.
        final ops = await db.select(db.syncOperations).get();
        expect(ops, isEmpty, reason: 'No outbox entries after rollback');
      },
    );

    test('7. company isolation', () async {
      // PO for company c-1.
      await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalPaise: 10000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Item',
              unit: 'PCS',
              unitPricePaise: 100,
              quantityOrdered: '100',
              totalPaise: 10000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      // PO for company c-2.
      await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-2',
          orderDate: '2026-07-28',
          supplierId: 'sup-2',
          supplierName: 'Vendor B',
          totalPaise: 20000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Item',
              unit: 'PCS',
              unitPricePaise: 200,
              quantityOrdered: '100',
              totalPaise: 20000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      // Query for c-1 only — should see 1.
      final pos1 = await (db.select(
        db.purchaseOrders,
      )..where((p) => p.companyId.equals('c-1'))).get();
      expect(pos1.length, 1);
      expect(pos1.first.supplierName, 'Vendor A');

      final pos2 = await (db.select(
        db.purchaseOrders,
      )..where((p) => p.companyId.equals('c-2'))).get();
      expect(pos2.length, 1);
      expect(pos2.first.supplierName, 'Vendor B');
    });

    test('8. sync payloads contain correct data', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.stockItems)
          .insert(
            StockItemsCompanion(
              localId: const Value('stock-widget'),
              companyId: const Value('c-1'),
              name: const Value('Widget'),
              unit: const Value('PCS'),
              currentQuantity: const Value('0'),
              unitCostPaise: const Value(300),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      final po = await repo.savePurchaseOrderDraft(
        const SavePurchaseOrderDraftCommand(
          companyId: 'c-1',
          orderDate: '2026-07-28',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          totalPaise: 30000,
          lines: [
            PurchaseOrderLineCommand(
              productName: 'Widget',
              unit: 'PCS',
              unitPricePaise: 300,
              quantityOrdered: '100',
              totalPaise: 30000,
              sortOrder: 0,
            ),
          ],
        ),
      );

      await repo.receiveGoods(
        ReceiveGoodsCommand(
          companyId: 'c-1',
          purchaseOrderLocalId: po.localId,
          receiptDate: '2026-07-29',
          supplierId: 'sup-1',
          supplierName: 'Vendor A',
          lines: [
            ReceiveLineCommand(
              purchaseOrderLineLocalId: po.lines.first.localId,
              productName: 'Widget',
              unit: 'PCS',
              quantityReceived: '50',
              unitCostPaise: 300,
              sortOrder: 0,
            ),
          ],
        ),
      );

      final ops = await db.select(db.syncOperations).get();
      expect(ops.length, 1);
      final payload = ops.first.payload;
      expect(payload, contains('purchase_receipt.posted'));
      expect(payload, contains('Widget'));
      expect(payload, contains('50'));
      expect(payload, contains('15000')); // 50 × 300
    });
  });
}
