/// Inventory posting service — records stock movements via the backend API.
///
/// Handles inventory valuation, stock-in, stock-out, and adjustments.
/// Uses the live inventory-adjustments API — no stubs, no mock data.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';

/// Inventory movement direction.
enum StockMovementType { in_, out, adjustment, transfer }

/// A single stock movement record returned from the backend.
class StockMovement {
  const StockMovement({
    required this.productId,
    required this.quantity,
    required this.unitValue,
    required this.type,
    this.warehouseId,
    this.referenceId,
    this.description,
  });

  final String productId;
  final double quantity;
  final double unitValue;
  final StockMovementType type;
  final String? warehouseId;
  final String? referenceId;
  final String? description;

  double get totalValue => quantity * unitValue;

  factory StockMovement.fromJson(Map<String, dynamic> json) =>
      StockMovement(
        productId: json['product_id'] as String? ?? json['item_id'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitValue: (json['unit_value'] as num?)?.toDouble() ?? (json['unit_price'] as num?)?.toDouble() ?? 0,
        type: _parseType(json['type'] as String?),
        warehouseId: json['warehouse_id'] as String?,
        referenceId: json['reference_id'] as String?,
        description: json['description'] as String?,
      );

  static StockMovementType _parseType(String? t) {
    switch (t?.toLowerCase()) {
      case 'in':
      case 'purchase':
      case 'receipt':
        return StockMovementType.in_;
      case 'out':
      case 'sale':
      case 'issue':
        return StockMovementType.out;
      case 'adjustment':
        return StockMovementType.adjustment;
      case 'transfer':
        return StockMovementType.transfer;
      default:
        return StockMovementType.adjustment;
    }
  }
}

/// Inventory posting service.
///
/// Records stock movements via `POST /inventory-adjustments` on the backend.
/// The backend handles inventory valuation, warehouse stock levels, and
/// ledger integration automatically.
class InventoryPostingService {
  InventoryPostingService(this._dio);
  final Dio _dio;

  /// Record stock-in (purchase, receipt, production).
  Future<Result<List<StockMovement>>> recordStockIn({
    required String productId,
    required double quantity,
    required double unitValue,
    String? warehouseId,
    String? purchaseOrderId,
  }) async {
    try {
      final res = await _dio.post('/inventory-adjustments', data: {
        'type': 'IN',
        'items': [
          {
            'product_id': productId,
            'quantity': quantity,
            'unit_value': unitValue,
            if (warehouseId != null) 'warehouse_id': warehouseId,
          },
        ],
        if (purchaseOrderId != null) 'reference_id': purchaseOrderId,
        'description': 'Stock in — purchase/receipt',
      });

      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
              .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
              .toList()
          : <StockMovement>[];
      return Success(items);
    } on DioException catch (e) {
      return Failure(
          ApiError.network(e.message ?? 'Failed to record stock-in'));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Record stock-out (sale, consumption, wastage).
  Future<Result<List<StockMovement>>> recordStockOut({
    required String productId,
    required double quantity,
    required double unitValue,
    String? warehouseId,
    String? invoiceId,
  }) async {
    try {
      final res = await _dio.post('/inventory-adjustments', data: {
        'type': 'OUT',
        'items': [
          {
            'product_id': productId,
            'quantity': -quantity,  // negative for stock-out
            'unit_value': unitValue,
            if (warehouseId != null) 'warehouse_id': warehouseId,
          },
        ],
        if (invoiceId != null) 'reference_id': invoiceId,
        'description': 'Stock out — sale/consumption',
      });

      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
              .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
              .toList()
          : <StockMovement>[];
      return Success(items);
    } on DioException catch (e) {
      return Failure(
          ApiError.network(e.message ?? 'Failed to record stock-out'));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Record stock adjustment (damage, loss, write-off).
  Future<Result<List<StockMovement>>> recordAdjustment({
    required String productId,
    required double quantity,
    required double unitValue,
    required String reason,
    String? warehouseId,
  }) async {
    try {
      final res = await _dio.post('/inventory-adjustments', data: {
        'type': 'ADJUSTMENT',
        'items': [
          {
            'product_id': productId,
            'quantity': quantity,
            'unit_value': unitValue,
            if (warehouseId != null) 'warehouse_id': warehouseId,
          },
        ],
        'description': reason,
      });

      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
              .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
              .toList()
          : <StockMovement>[];
      return Success(items);
    } on DioException catch (e) {
      return Failure(
          ApiError.network(e.message ?? 'Failed to record adjustment'));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final inventoryPostingServiceProvider = Provider<InventoryPostingService>((
  ref,
) {
  return InventoryPostingService(ref.watch(apiClientProvider));
});
