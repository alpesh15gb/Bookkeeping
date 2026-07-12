/// Warehouse models and services.
///
/// Even though the backend may not yet expose warehouse endpoints,
/// the frontend model supports multi-warehouse stock tracking.
library;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';

/// Warehouse entity.
@immutable
class Warehouse {
  const Warehouse({
    required this.id,
    this.name = '',
    this.code = '',
    this.location,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String code;
  final String? location;
  final bool isActive;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    code: json['code'] as String? ?? '',
    location: json['location'] as String?,
    isActive: json['is_active'] as bool? ?? true,
  );
}

/// Warehouse service.
class WarehouseService {
  WarehouseService(this._dio);
  final Dio _dio;

  Future<Result<List<Warehouse>>> list({int page = 1, int limit = 50}) {
    return guardDio(() async {
      final res = await _dio.get(
        '/warehouses',
        queryParameters: {'page': page, 'limit': limit},
      );
      return (res.data as List)
          .map((e) => Warehouse.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<Warehouse>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/warehouses/$id');
      return Warehouse.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final warehouseServiceProvider = Provider<WarehouseService>((ref) {
  return WarehouseService(ref.watch(apiClientProvider));
});
