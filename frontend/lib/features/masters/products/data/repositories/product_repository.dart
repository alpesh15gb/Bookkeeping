/// Repository for /masters/products.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/product.dart';

class ProductRepository extends BaseRepository<Product> {
  ProductRepository(this._dio, CacheService cache) : super(_dio, cache);

  final Dio _dio;

  @override
  String get path => '/masters/products';
  @override
  String get cachePrefix => 'products';
  @override
  Product parseOne(Map<String, dynamic> json) =>
      const Product(id: '', name: '').fromJson(json);

  Future<Result<Product>> lookupBarcode(String code) {
    return guardDio(() async {
      final response = await _dio.get(
        '$path/barcode/lookup',
        queryParameters: {'code': code.trim()},
      );
      return parseOne(response.data as Map<String, dynamic>);
    });
  }
}
