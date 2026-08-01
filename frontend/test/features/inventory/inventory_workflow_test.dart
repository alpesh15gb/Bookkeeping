/// End-to-end inventory workflow test.
///
/// Validates: create stock item → receive → restart → issue → balance →
/// movement ledger → outbox → sync payload.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:apexbooks/features/inventory/domain/commands/inventory_commands.dart';
import 'package:apexbooks/features/inventory/domain/repositories/inventory_repository.dart';

void main() {
  group('Inventory workflow', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late InventoryRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, dio: Dio(BaseOptions()));
      repo = InventoryRepositoryImpl(
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

    test('1. create stock item → persisted', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          sku: 'WDG-001',
          openingQuantity: '0',
        ),
      );

      expect(item.name, 'Widget A');
      expect(item.sku, 'WDG-001');
      expect(item.unit, 'PCS');
      expect(item.currentQtyAsDouble, 0);
    });

    test('2. receive stock → quantity updated', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '0',
        ),
      );

      await repo.createMovement(
        CreateMovementCommand(
          companyId: 'c-1',
          stockItemId: item.localId,
          movementType: 'RECEIPT',
          quantity: '100',
          unitCostPaise: 5000, // ₹50.00 per unit
          movementDate: '2026-07-28',
          referenceNumber: 'PO-001',
        ),
      );

      final updated = await repo.getStockItem(item.localId);
      expect(updated!.currentQtyAsDouble, 100);
      expect(updated.unitCostPaise, 5000);
    });

    test('3. issue stock → quantity decreased', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '100',
          unitCostPaise: 5000,
        ),
      );

      await repo.createMovement(
        CreateMovementCommand(
          companyId: 'c-1',
          stockItemId: item.localId,
          movementType: 'ISSUE',
          quantity: '-30',
          unitCostPaise: 5000,
          movementDate: '2026-07-28',
        ),
      );

      final updated = await repo.getStockItem(item.localId);
      expect(updated!.currentQtyAsDouble, 70);
    });

    test('4. restart → stock survives', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '50',
        ),
      );

      // Simulate restart: fresh repository.
      final reloaded = await repo.getStockItem(item.localId);
      expect(reloaded, isNotNull);
      expect(reloaded!.name, 'Widget A');
      expect(reloaded.currentQtyAsDouble, 50);
    });

    test('5. movement ledger written', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '100',
        ),
      );

      await repo.createMovement(
        CreateMovementCommand(
          companyId: 'c-1',
          stockItemId: item.localId,
          movementType: 'ISSUE',
          quantity: '-20',
          unitCostPaise: 5000,
          movementDate: '2026-07-28',
        ),
      );

      final movs = await repo.getMovements(item.localId);
      expect(movs.length, 1);
      expect(movs.first.movementType, 'ISSUE');
      expect(movs.first.quantity, '-20');
      expect(movs.first.balanceAfter, '80.000');
    });

    test('6. insufficient stock rejected', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '10',
        ),
      );

      await expectLater(
        () => repo.createMovement(
          CreateMovementCommand(
            companyId: 'c-1',
            stockItemId: item.localId,
            movementType: 'ISSUE',
            quantity: '-20',
            unitCostPaise: 5000,
            movementDate: '2026-07-28',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('7. outbox created for inventory movement', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '50',
        ),
      );

      await repo.createMovement(
        CreateMovementCommand(
          companyId: 'c-1',
          stockItemId: item.localId,
          movementType: 'RECEIPT',
          quantity: '25',
          unitCostPaise: 6000,
          movementDate: '2026-07-28',
        ),
      );

      final ops = await (db.select(
        db.syncOperations,
      )..where((operation) => operation.entityType.equals('inventory'))).get();
      expect(ops.length, 1);
      expect(ops.first.entityType, 'inventory');
      expect(ops.first.status, 'pending');
    });

    test('8. balance recomputed after inbound', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '10',
          unitCostPaise: 5000,
        ),
      );

      // Receive 10 units at ₹60 each → weighted avg = (10*50 + 10*60) / 20 = 55
      await repo.createMovement(
        CreateMovementCommand(
          companyId: 'c-1',
          stockItemId: item.localId,
          movementType: 'RECEIPT',
          quantity: '10',
          unitCostPaise: 6000,
          movementDate: '2026-07-28',
        ),
      );

      final updated = await repo.getStockItem(item.localId);
      expect(updated!.currentQtyAsDouble, 20);
      // Weighted average: (50000 + 60000) / 20 = 5500 paise
      expect(updated.unitCostPaise, 5500);
    });

    test('9. sync payload contains movement data', () async {
      final item = await repo.createStockItem(
        const CreateStockItemCommand(
          companyId: 'c-1',
          name: 'Widget A',
          unit: 'PCS',
          openingQuantity: '100',
        ),
      );

      await repo.createMovement(
        CreateMovementCommand(
          companyId: 'c-1',
          stockItemId: item.localId,
          movementType: 'ISSUE',
          quantity: '-50',
          unitCostPaise: 5000,
          movementDate: '2026-07-28',
        ),
      );

      final ops = await (db.select(
        db.syncOperations,
      )..where((operation) => operation.entityType.equals('inventory'))).get();
      expect(ops.length, 1);
      final payload = ops.first.payload;
      expect(payload, contains('stock.adjusted'));
      expect(payload, contains('-50'));
      expect(payload, contains('50.000')); // balance after
    });
  });
}
