/// Repository for /masters/products.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../models/product.dart';

class ProductRepository extends BaseRepository<Product> {
  ProductRepository(Dio dio, CacheService cache) : super(dio, cache);

  @override
  String get path => '/masters/products';
  @override
  String get cachePrefix => 'products';
  @override
  Product parseOne(Map<String, dynamic> json) =>
      const Product(id: '', name: '').fromJson(json);
}
