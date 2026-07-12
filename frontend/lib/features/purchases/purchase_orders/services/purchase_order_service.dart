/// Purchase order API service — CRUD + confirm/cancel transitions.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_status.dart';

class PurchaseOrderService {
  PurchaseOrderService(this._dio);
  final Dio _dio;

  Future<Result<PurchaseOrder>> create(PurchaseOrder po) {
    return guardDio(() async {
      final res = await _dio.post(
        '/purchase-orders',
        data: po.toCreatePayload(),
      );
      return PurchaseOrder.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<PurchaseOrderListItem>>> list({
    int page = 1,
    int limit = 50,
    PurchaseOrderStatus? status,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null) 'status': status.value,
      };
      final res = await _dio.get('/purchase-orders', queryParameters: q);
      return (res.data as List)
          .map((e) => PurchaseOrderListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<PurchaseOrder>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/purchase-orders/$id');
      return PurchaseOrder.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Confirm a draft PO.
  Future<Result<PurchaseOrder>> confirm(String id) {
    return guardDio(() async {
      final res = await _dio.post('/purchase-orders/$id/confirm');
      return PurchaseOrder.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Cancel a draft or confirmed PO.
  Future<Result<PurchaseOrder>> cancel(String id) {
    return guardDio(() async {
      final res = await _dio.post('/purchase-orders/$id/cancel');
      return PurchaseOrder.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final purchaseOrderServiceProvider = Provider<PurchaseOrderService>((ref) {
  return PurchaseOrderService(ref.watch(apiClientProvider));
});
