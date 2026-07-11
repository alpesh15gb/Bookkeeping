/// Inventory adjustment services — create, list, confirm adjustments.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';

/// An adjustment line — changes stock for one product.
@immutable
class AdjustmentLine {
  const AdjustmentLine({
    this.id,
    required this.productId,
    this.productName = '',
    required this.quantityChange,
    this.unitCost,
    this.totalCost = 0,
  });

  final String? id;
  final String productId;
  final String productName;
  final double quantityChange;
  final double? unitCost;
  final double totalCost;

  bool get isIncrease => quantityChange > 0;

  AdjustmentLine copyWith({
    String? id,
    String? productId,
    String? productName,
    double? quantityChange,
    double? unitCost,
    double? totalCost,
  }) => AdjustmentLine(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    quantityChange: quantityChange ?? this.quantityChange,
    unitCost: unitCost ?? this.unitCost,
    totalCost: totalCost ?? this.totalCost,
  );

  Map<String, dynamic> toCreatePayload() => {
    'product_id': productId,
    'quantity_change': quantityChange,
    if (unitCost != null) 'unit_cost': unitCost,
  };

  factory AdjustmentLine.fromJson(Map<String, dynamic> json) => AdjustmentLine(
    id: (json['id'] ?? '').toString(),
    productId: (json['product_id'] ?? '').toString(),
    productName: json['product_name'] as String? ?? '',
    quantityChange: (json['quantity_change'] as num?)?.toDouble() ?? 0,
    unitCost: (json['unit_cost'] as num?)?.toDouble(),
    totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0,
  );
}

/// Inventory adjustment header.
@immutable
class InventoryAdjustment {
  const InventoryAdjustment({
    required this.id,
    this.adjustmentNumber = '',
    this.adjustmentDate = '',
    this.reason,
    this.status = 'DRAFT',
    this.lines = const [],
    this.createdAt,
  });

  final String id;
  final String adjustmentNumber;
  final String adjustmentDate;
  final String? reason;
  final String status;
  final List<AdjustmentLine> lines;
  final String? createdAt;

  bool get isDraft => status == 'DRAFT';
  bool get isConfirmed => status == 'CONFIRMED';

  factory InventoryAdjustment.fromJson(Map<String, dynamic> json) =>
      InventoryAdjustment(
        id: (json['id'] ?? '').toString(),
        adjustmentNumber: json['adjustment_number'] as String? ?? '',
        adjustmentDate: json['adjustment_date'] as String? ?? '',
        reason: json['reason'] as String?,
        status: json['status'] as String? ?? 'DRAFT',
        lines:
            (json['lines'] as List?)
                ?.map((e) => AdjustmentLine.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['created_at'] as String?,
      );
}

/// Adjustment list item (lightweight).
@immutable
class AdjustmentListItem {
  const AdjustmentListItem({
    required this.id,
    this.adjustmentNumber = '',
    this.adjustmentDate = '',
    this.status = 'DRAFT',
    this.createdAt,
  });

  final String id;
  final String adjustmentNumber;
  final String adjustmentDate;
  final String status;
  final String? createdAt;

  factory AdjustmentListItem.fromJson(Map<String, dynamic> json) =>
      AdjustmentListItem(
        id: (json['id'] ?? '').toString(),
        adjustmentNumber: json['adjustment_number'] as String? ?? '',
        adjustmentDate: json['adjustment_date'] as String? ?? '',
        status: json['status'] as String? ?? 'DRAFT',
        createdAt: json['created_at'] as String?,
      );
}

/// Adjustment service — CRUD + confirm.
class AdjustmentService {
  AdjustmentService(this._dio);
  final Dio _dio;

  Future<Result<InventoryAdjustment>> create({
    required String adjustmentNumber,
    required String adjustmentDate,
    String? reason,
    required List<AdjustmentLine> lines,
  }) async {
    try {
      final payload = <String, dynamic>{
        'adjustment_number': adjustmentNumber,
        'adjustment_date': adjustmentDate,
        if (reason != null) 'reason': reason,
        'line_items': [...lines.map((l) => l.toCreatePayload())],
      };
      final res = await _dio.post('/inventory-adjustments', data: payload);
      return Success(
        InventoryAdjustment.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<AdjustmentListItem>>> list({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/inventory-adjustments',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map((e) => AdjustmentListItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<InventoryAdjustment>> get(String id) async {
    try {
      final res = await _dio.get('/inventory-adjustments/$id');
      return Success(
        InventoryAdjustment.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<InventoryAdjustment>> confirm(String id) async {
    try {
      final res = await _dio.post('/inventory-adjustments/$id/confirm');
      return Success(
        InventoryAdjustment.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final adjustmentServiceProvider = Provider<AdjustmentService>((ref) {
  return AdjustmentService(ref.watch(apiClientProvider));
});
