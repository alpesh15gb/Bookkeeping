/// Repository interface for inventory management.
library;

import '../entities/inventory_entities.dart';
import '../commands/inventory_commands.dart';

abstract interface class InventoryRepository {
  // ── Stock items ──────────────────────────────────────────────────────────

  Stream<List<StockItemEntity>> watchStockItems({String? companyId});
  Future<StockItemEntity?> getStockItem(String localId, {String? companyId});
  Future<StockItemEntity> createStockItem(CreateStockItemCommand command);

  // ── Movements ────────────────────────────────────────────────────────────

  /// Create a stock movement.  Atomically:
  /// 1. Creates the movement ledger entry.
  /// 2. Updates the stock item's current quantity.
  /// 3. Updates/creates the inventory balance.
  /// 4. Queues the sync operation.
  Future<InventoryMovementEntity> createMovement(CreateMovementCommand command);

  Stream<List<InventoryMovementEntity>> watchMovements(String stockItemId);
  Future<List<InventoryMovementEntity>> getMovements(String stockItemId);
}
