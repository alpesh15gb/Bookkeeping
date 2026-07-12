/// Shared warehouse providers — reused by goods receipts, transfers, and the
/// warehouse module. Backed by the existing [WarehouseService].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';
import 'package:apexbooks/features/inventory/stock/presentation/inventory_list_screen.dart';
import 'package:apexbooks/features/inventory/movements/services/movement_service.dart';
import '../services/warehouse_service.dart';

/// List all warehouses.
final warehouseListProvider = FutureProvider.autoDispose<List<Warehouse>>((
  ref,
) async {
  final res = await ref.watch(warehouseServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

/// Single warehouse detail.
final warehouseDetailProvider =
    FutureProvider.autoDispose.family<Warehouse, String>((ref, id) async {
  final res = await ref.watch(warehouseServiceProvider).get(id);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

/// Warehouse dashboard aggregated data.
final warehouseDashboardProvider =
    FutureProvider.autoDispose<WarehouseDashboardData>((ref) async {
  final warehousesAsync = ref.watch(warehouseListProvider);
  final warehouses = warehousesAsync.valueOrNull ?? <Warehouse>[];
  final stockAsync = ref.watch(stockBalancesProvider);
  final stock = stockAsync.valueOrNull ?? <StockBalance>[];

  final totalStockValue =
      stock.fold<double>(0, (a, b) => a + b.stockValue);
  final lowStockCount = stock.where((s) => s.isLowStock).length;
  final totalProducts = stock.where((s) => s.currentStock > 0).length;

  return WarehouseDashboardData(
    totalWarehouses: warehouses.length,
    totalProducts: totalProducts,
    totalStockValue: totalStockValue,
    lowStockCount: lowStockCount,
  );
});

/// Warehouse stock items derived from stock-ledger movements.
final warehouseStockProvider = FutureProvider.autoDispose
    .family<List<WarehouseStockItem>, String>((ref, warehouseId) async {
  final movementRes = await ref
      .watch(movementServiceProvider)
      .getAllMovements(warehouseId: warehouseId, limit: 500);
  final movements = switch (movementRes) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };

  // Aggregate movements by product to derive current stock.
  final Map<String, _StockAccum> acc = {};
  for (final m in movements) {
    final a = acc.putIfAbsent(
      m.productId,
      () => _StockAccum(
        productName: m.productName,
        sku: m.sku,
      ),
    );
    a.balance += m.quantity;
    if (m.rate > 0) a.rate = m.rate;
  }

  return acc.entries
      .map(
        (e) => WarehouseStockItem(
          productId: e.key,
          productName: e.value.productName,
          sku: e.value.sku,
          currentStock: e.value.balance,
          unitCost: e.value.rate,
        ),
      )
      .toList()
    ..sort((a, b) => a.productName.compareTo(b.productName));
});

/// Recent stock movements for a specific warehouse.
final warehouseMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, String>((ref, warehouseId) async {
  final res = await ref
      .watch(movementServiceProvider)
      .getAllMovements(warehouseId: warehouseId, limit: 50);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

/// Internal accumulator for warehouse stock aggregation.
class _StockAccum {
  _StockAccum({required this.productName, this.sku = ''});
  final String productName;
  final String sku;
  double balance = 0;
  double rate = 0;
}
