/// Goods receipt API service + inventory integration contract.
///
/// Per the posting contract: Goods Receipt confirmation must invoke
/// InventoryPostingService to record stock-in. This service provides the
/// API layer; the posting integration is orchestrated by the controller.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/goods_receipt.dart';

class GoodsReceiptService {
  GoodsReceiptService(this._dio);
  final Dio _dio;

  Future<Result<GoodsReceipt>> create(GoodsReceipt gr) async {
    try {
      final res = await _dio.post(
        '/goods-receipts',
        data: gr.toCreatePayload(),
      );
      return Success(GoodsReceipt.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<GoodsReceiptListItem>>> list({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/goods-receipts',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map((e) => GoodsReceiptListItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<GoodsReceipt>> get(String id) async {
    try {
      final res = await _dio.get('/goods-receipts/$id');
      return Success(GoodsReceipt.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Confirm a draft goods receipt — triggers stock-in posting.
  Future<Result<GoodsReceipt>> confirm(String id) async {
    try {
      final res = await _dio.post('/goods-receipts/$id/confirm');
      return Success(GoodsReceipt.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Cancel a confirmed goods receipt — reverses stock posting.
  Future<Result<GoodsReceipt>> cancel(String id) async {
    try {
      final res = await _dio.post('/goods-receipts/$id/cancel');
      return Success(GoodsReceipt.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final goodsReceiptServiceProvider = Provider<GoodsReceiptService>((ref) {
  return GoodsReceiptService(ref.watch(apiClientProvider));
});
