/// Stock service — API calls for stock ledger and product balance queries.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/stock_models.dart';

class StockService {
  StockService(this._dio);
  final Dio _dio;

  /// Get stock ledger movements for a product.
  Future<Result<List<StockMovement>>> getMovements({
    required String productId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/products/$productId/movements',
        queryParameters: {'page': page, 'limit': limit},
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

  /// Get current stock for all products (low stock check, balance).
  ///
  /// Uses the `/products` endpoint which includes `current_stock`,
  /// `reorder_level`, and `purchase_price` fields.
  Future<Result<List<StockBalance>>> getAllBalances({
    int page = 1,
    int limit = 200,
    bool? lowStock,
  }) async {
    try {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      final res = await _dio.get('/products', queryParameters: q);
      var items = (res.data as List)
          .map((e) => StockBalance.fromProductJson(e as Map<String, dynamic>))
          .toList();
      // Client-side low-stock filter when requested.
      if (lowStock == true) {
        items = items.where((b) => b.isLowStock).toList();
      }
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get stock balance for a single product.
  Future<Result<StockBalance>> getProductBalance(String productId) async {
    try {
      final res = await _dio.get('/products/$productId');
      final product = StockBalance.fromProductJson(
        res.data as Map<String, dynamic>,
      );
      return Success(product);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final stockServiceProvider = Provider<StockService>((ref) {
  return StockService(ref.watch(apiClientProvider));
});
