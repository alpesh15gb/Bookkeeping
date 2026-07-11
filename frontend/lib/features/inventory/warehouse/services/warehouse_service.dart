/// Warehouse models and services.
///
/// Even though the backend may not yet expose warehouse endpoints,
/// the frontend model supports multi-warehouse stock tracking.
library;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
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

  /// List all warehouses.
  Future<Result<List<Warehouse>>> list({int page = 1, int limit = 50}) async {
    try {
      final res = await _dio.get(
        '/warehouses',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map((e) => Warehouse.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get warehouse by ID.
  Future<Result<Warehouse>> get(String id) async {
    try {
      final res = await _dio.get('/warehouses/$id');
      return Success(Warehouse.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final warehouseServiceProvider = Provider<WarehouseService>((ref) {
  return WarehouseService(ref.watch(apiClientProvider));
});
