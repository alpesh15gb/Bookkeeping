/// Inter-warehouse transfer models and service.
///
/// Transfers represent stock movement from one warehouse to another.
/// The quantity is negative in the source warehouse and positive in the
/// destination warehouse.
library;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/utils/formatters.dart';

/// Transfer line item.
@immutable
class TransferLine {
  const TransferLine({
    required this.productId,
    this.productName = '',
    required this.quantity,
    this.rate = 0,
  });

  factory TransferLine.fromJson(Map<String, dynamic> json) => TransferLine(
    productId: (json['product_id'] ?? '').toString(),
    productName: json['product_name'] as String? ?? '',
    quantity: parseDoubleSafe(json['quantity']),
    rate: parseDoubleSafe(json['rate']),
  );

  TransferLine copyWith({
    String? productId,
    String? productName,
    double? quantity,
    double? rate,
  }) => TransferLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    quantity: quantity ?? this.quantity,
    rate: rate ?? this.rate,
  );

  final String productId;
  final String productName;
  final double quantity;
  final double rate;
}

/// Inter-warehouse transfer.
@immutable
class Transfer {
  const Transfer({
    required this.id,
    this.transferNumber = '',
    this.transferDate = '',
    required this.fromWarehouseId,
    this.fromWarehouseName = '',
    required this.toWarehouseId,
    this.toWarehouseName = '',
    this.status = 'DRAFT',
    this.lines = const [],
    this.createdAt,
  });

  final String id;
  final String transferNumber;
  final String transferDate;
  final String fromWarehouseId;
  final String fromWarehouseName;
  final String toWarehouseId;
  final String toWarehouseName;
  final String status;
  final List<TransferLine> lines;
  final String? createdAt;

  bool get isDraft => status == 'DRAFT';
  bool get isCompleted => status == 'COMPLETED';

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
    id: (json['id'] ?? '').toString(),
    transferNumber: json['transfer_number'] as String? ?? '',
    transferDate: json['transfer_date'] as String? ?? '',
    fromWarehouseId: (json['from_warehouse_id'] ?? '').toString(),
    fromWarehouseName: json['from_warehouse_name'] as String? ?? '',
    toWarehouseId: (json['to_warehouse_id'] ?? '').toString(),
    toWarehouseName: json['to_warehouse_name'] as String? ?? '',
    status: json['status'] as String? ?? 'DRAFT',
    lines:
        (json['lines'] as List?)
            ?.map((e) => TransferLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    createdAt: json['created_at'] as String?,
  );
}

/// Transfer service.
class TransferService {
  TransferService(this._dio);
  final Dio _dio;

  Future<Result<Transfer>> create(Map<String, dynamic> payload) {
    return guardDio(() async {
      final res = await _dio.post('/transfers', data: payload);
      return Transfer.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<Transfer>>> list({int page = 1, int limit = 50}) {
    return guardDio(() async {
      final res = await _dio.get(
        '/transfers',
        queryParameters: {'page': page, 'limit': limit},
      );
      return (res.data as List)
          .map((e) => Transfer.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<Transfer>> complete(String id) {
    return guardDio(() async {
      final res = await _dio.post('/transfers/$id/complete');
      return Transfer.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final transferServiceProvider = Provider<TransferService>((ref) {
  return TransferService(ref.watch(apiClientProvider));
});
