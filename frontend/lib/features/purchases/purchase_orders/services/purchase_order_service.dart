/// Purchase order API service — CRUD + confirm/cancel transitions.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_status.dart';

class PurchaseOrderService {
  PurchaseOrderService(this._dio);
  final Dio _dio;

  Future<Result<PurchaseOrder>> create(PurchaseOrder po) async {
    try {
      final res = await _dio.post(
        '/purchase-orders',
        data: po.toCreatePayload(),
      );
      return Success(PurchaseOrder.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<PurchaseOrderListItem>>> list({
    int page = 1,
    int limit = 50,
    PurchaseOrderStatus? status,
  }) async {
    try {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (status != null) 'status': status.value,
      };
      final res = await _dio.get('/purchase-orders', queryParameters: q);
      final items = (res.data as List)
          .map((e) => PurchaseOrderListItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<PurchaseOrder>> get(String id) async {
    try {
      final res = await _dio.get('/purchase-orders/$id');
      return Success(PurchaseOrder.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Confirm a draft PO.
  Future<Result<PurchaseOrder>> confirm(String id) async {
    try {
      final res = await _dio.post('/purchase-orders/$id/confirm');
      return Success(PurchaseOrder.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Cancel a draft or confirmed PO.
  Future<Result<PurchaseOrder>> cancel(String id) async {
    try {
      final res = await _dio.post('/purchase-orders/$id/cancel');
      return Success(PurchaseOrder.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final purchaseOrderServiceProvider = Provider<PurchaseOrderService>((ref) {
  return PurchaseOrderService(ref.watch(apiClientProvider));
});
