/// Movement service — combined view of stock movements across all sources.
///
/// Provides history and audit trail functionality. The movement is the source
/// of truth; current stock is derived from movement history.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';

class MovementService {
  MovementService(this._dio);
  final Dio _dio;

  /// Get movement history for a product (paginated).
  Future<Result<List<StockMovement>>> getProductHistory({
    required String productId,
    int page = 1,
    int limit = 50,
    String? referenceType,
  }) async {
    try {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (referenceType != null) 'reference_type': referenceType,
      };
      final res = await _dio.get(
        '/products/$productId/stock-ledger',
        queryParameters: q,
      );
      final items = (res.data as List)
          .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get movement history across all products (admin view).
  Future<Result<List<StockMovement>>> getAllMovements({
    int page = 1,
    int limit = 50,
    String? productId,
    String? referenceType,
  }) async {
    try {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (productId != null) 'product_id': productId,
        if (referenceType != null) 'reference_type': referenceType,
      };
      final res = await _dio.get('/stock-ledger', queryParameters: q);
      final items = (res.data as List)
          .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
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
