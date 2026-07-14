/// Movement service — combined view of stock movements across all sources.
///
/// Provides history and audit trail functionality. The movement is the source
/// of truth; current stock is derived from movement history.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';

class MovementService {
  MovementService(this._dio);
  final Dio _dio;

  Future<Result<List<StockMovement>>> getProductHistory({
    required String productId,
    int page = 1,
    int limit = 50,
    String? referenceType,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{
        'product_id': productId,
        'page': page,
        'limit': limit.clamp(1, 100),
        if (referenceType != null) 'reference_type': referenceType,
      };
      final res = await _dio.get('/stock-ledger', queryParameters: q);
      final rows = res.data;
      if (rows is! List) {
        throw const FormatException('Invalid stock movement response.');
      }
      return rows
          .whereType<Map>()
          .map((e) => StockMovement.fromJson(e.cast<String, dynamic>()))
          .toList();
    });
  }

  Future<Result<List<StockMovement>>> getAllMovements({
    int page = 1,
    int limit = 50,
    String? productId,
    String? referenceType,
    String? warehouseId,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit.clamp(1, 100),
        if (productId != null) 'product_id': productId,
        if (referenceType != null) 'reference_type': referenceType,
        if (warehouseId != null) 'warehouse_id': warehouseId,
      };
      final res = await _dio.get('/stock-ledger', queryParameters: q);
      final rows = res.data;
      if (rows is! List) {
        throw const FormatException('Invalid stock movement response.');
      }
      return rows
          .whereType<Map>()
          .map((e) => StockMovement.fromJson(e.cast<String, dynamic>()))
          .toList();
    });
  }

  /// Loads the complete movement history needed to derive a warehouse's
  /// balance. The API caps pages at 100 rows, so aggregation must page rather
  /// than silently calculating from only the newest movements.
  Future<Result<List<StockMovement>>> getWarehouseMovementHistory(
    String warehouseId,
  ) {
    return guardDio(() async {
      const pageSize = 100;
      var page = 1;
      final movements = <StockMovement>[];
      while (true) {
        final res = await _dio.get(
          '/stock-ledger',
          queryParameters: {
            'page': page,
            'limit': pageSize,
            'warehouse_id': warehouseId,
          },
        );
        final rows = res.data as List;
        movements.addAll(
          rows.map((e) => StockMovement.fromJson(e as Map<String, dynamic>)),
        );
        if (rows.length < pageSize) break;
        page += 1;
      }
      return movements;
    });
  }

  /// Reconcile current stock by replaying movements.
  /// Returns the calculated balance from movement history.
  double calculateBalanceFromMovements(List<StockMovement> movements) {
    double balance = 0;
    for (final m in movements) {
      balance += m.quantity;
    }
    return balance;
  }
}

final movementServiceProvider = Provider<MovementService>((ref) {
  return MovementService(ref.watch(apiClientProvider));
});
