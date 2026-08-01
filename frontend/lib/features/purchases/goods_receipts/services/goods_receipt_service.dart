/// Goods receipt API service + inventory integration contract.
///
/// Per the posting contract: Goods Receipt confirmation must invoke
/// InventoryPostingService to record stock-in. This service provides the
/// API layer; the posting integration is orchestrated by the controller.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/goods_receipt.dart';

class GoodsReceiptService {
  GoodsReceiptService(this._dio);
  final Dio _dio;

  Future<Result<GoodsReceipt>> create(GoodsReceipt gr) {
    return guardDio(() async {
      final res = await _dio.post(
        '/goods-receipts',
        data: gr.toCreatePayload(),
      );
      return GoodsReceipt.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<GoodsReceiptListItem>>> list({
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/goods-receipts',
        queryParameters: {'page': page, 'limit': limit},
      );
      final body = res.data as Map<String, dynamic>;
      return ((body['items'] as List?) ?? const [])
          .map((e) => GoodsReceiptListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<GoodsReceipt>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/goods-receipts/$id');
      return GoodsReceipt.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<GoodsReceipt>> confirm(String id) {
    return guardDio(() async {
      final res = await _dio.post('/goods-receipts/$id/confirm');
      return GoodsReceipt.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<GoodsReceipt>> cancel(String id) {
    return guardDio(() async {
      final res = await _dio.post('/goods-receipts/$id/cancel');
      return GoodsReceipt.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final goodsReceiptServiceProvider = Provider<GoodsReceiptService>((ref) {
  return GoodsReceiptService(ref.watch(apiClientProvider));
});
