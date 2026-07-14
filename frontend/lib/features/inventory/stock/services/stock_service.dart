/// Stock service — API calls for stock ledger and product balance queries.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/stock_models.dart';

class StockService {
  StockService(this._dio);
  final Dio _dio;

  Future<Result<List<StockMovement>>> getMovements({
    required String productId,
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/stock-ledger',
        queryParameters: {
          'product_id': productId,
          'page': page,
          'limit': limit.clamp(1, 100),
        },
      );
      return (res.data as List)
          .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<StockBalance>>> getAllBalances({
    int page = 1,
    int limit = 100,
    bool? lowStock,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{'page': page, 'limit': limit.clamp(1, 100)};
      final res = await _dio.get('/masters/products', queryParameters: q);
      final rows = res.data;
      if (rows is! List) {
        throw const FormatException('Invalid product stock response.');
      }
      var items = rows
          .whereType<Map>()
          .map((e) => StockBalance.fromProductJson(e.cast<String, dynamic>()))
          .toList();
      if (lowStock == true) {
        items = items.where((b) => b.isLowStock).toList();
      }
      return items;
    });
  }

  Future<Result<StockBalance>> getProductBalance(String productId) {
    return guardDio(() async {
      final res = await _dio.get('/masters/products/$productId');
      return StockBalance.fromProductJson(res.data as Map<String, dynamic>);
    });
  }
}

final stockServiceProvider = Provider<StockService>((ref) {
  return StockService(ref.watch(apiClientProvider));
});
