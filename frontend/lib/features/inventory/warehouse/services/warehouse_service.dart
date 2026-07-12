/// Warehouse models and services.
///
/// Manages multi-location inventory stock locations and warehouse-specific
/// stock views.
library;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';

/// Physical address for a warehouse.
@immutable
class WarehouseAddress {
  const WarehouseAddress({
    this.street,
    this.city,
    this.state,
    this.pincode,
  });

  final String? street;
  final String? city;
  final String? state;
  final String? pincode;

  factory WarehouseAddress.fromJson(Map<String, dynamic> json) =>
      WarehouseAddress(
        street: json['street'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        pincode: json['pincode'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (street != null) 'street': street,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        if (pincode != null) 'pincode': pincode,
      };

  String get formatted {
    final parts = [street, city, state, pincode].where(
      (p) => p != null && p.isNotEmpty,
    );
    return parts.isEmpty ? '' : parts.join(', ');
  }
}

/// Warehouse entity.
@immutable
class Warehouse {
  const Warehouse({
    required this.id,
    this.name = '',
    this.code = '',
    this.location,
    this.isActive = true,
    this.gstin,
    this.address,
    this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String? location;
  final bool isActive;
  final String? gstin;
  final WarehouseAddress? address;
  final String? createdAt;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: (json['id'] ?? '').toString(),
        name: json['name'] as String? ?? '',
        code: json['code'] as String? ?? '',
        location: json['location'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        gstin: json['gstin'] as String?,
        address: json['address'] != null
            ? WarehouseAddress.fromJson(
                json['address'] as Map<String, dynamic>,
              )
            : null,
        createdAt: json['created_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'code': code,
        if (location != null) 'location': location,
        'is_active': isActive,
        if (gstin != null) 'gstin': gstin,
        if (address != null) 'address': address!.toJson(),
      };
}

/// A warehouse-stock view: product-level balance for a single warehouse.
@immutable
class WarehouseStockItem {
  const WarehouseStockItem({
    required this.productId,
    required this.productName,
    this.sku = '',
    this.currentStock = 0,
    this.reorderLevel = 0,
    this.unitCost = 0,
  });

  final String productId;
  final String productName;
  final String sku;
  final double currentStock;
  final double reorderLevel;
  final double unitCost;

  double get stockValue => currentStock * unitCost;
  bool get isLowStock => reorderLevel > 0 && currentStock <= reorderLevel;
  bool get isOutOfStock => currentStock <= 0.001;
}

/// KPI snapshot for the warehouse dashboard.
@immutable
class WarehouseDashboardData {
  const WarehouseDashboardData({
    this.totalWarehouses = 0,
    this.totalProducts = 0,
    this.totalStockValue = 0,
    this.lowStockCount = 0,
  });

  final int totalWarehouses;
  final int totalProducts;
  final double totalStockValue;
  final int lowStockCount;
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

  Future<Result<Warehouse>> create(Map<String, dynamic> payload) {
    return guardDio(() async {
      final res = await _dio.post('/warehouses', data: payload);
      return Warehouse.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<Warehouse>> update(String id, Map<String, dynamic> payload) {
    return guardDio(() async {
      final res = await _dio.put('/warehouses/$id', data: payload);
      return Warehouse.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<void>> delete(String id) {
    return guardDio(() async {
      await _dio.delete('/warehouses/$id');
    });
  }
}

final warehouseServiceProvider = Provider<WarehouseService>((ref) {
  return WarehouseService(ref.watch(apiClientProvider));
});
