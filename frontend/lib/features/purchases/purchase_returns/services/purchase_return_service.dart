/// Purchase return API service.
///
/// Per the posting contract: Return posting must invoke
/// InventoryPostingService (stock-out reversal) and
/// PayablePostingService (reduce vendor payable / create debit note).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_return.dart';

class PurchaseReturnService {
  PurchaseReturnService(this._dio);
  final Dio _dio;

  Future<Result<PurchaseReturn>> create(PurchaseReturn ret) {
    return guardDio(() async {
      final res = await _dio.post(
        '/purchase-returns',
        data: ret.toCreatePayload(),
      );
      return PurchaseReturn.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<PurchaseReturnListItem>>> list({
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/purchase-returns',
        queryParameters: {'page': page, 'limit': limit},
      );
      return (res.data as List)
          .map((e) => PurchaseReturnListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<PurchaseReturn>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/purchase-returns/$id');
      return PurchaseReturn.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<PurchaseReturn>> post(String id) {
    return guardDio(() async {
      final res = await _dio.post('/purchase-returns/$id/post');
      return PurchaseReturn.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<PurchaseReturn>> cancel(String id) {
    return guardDio(() async {
      final res = await _dio.post('/purchase-returns/$id/cancel');
      return PurchaseReturn.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final purchaseReturnServiceProvider = Provider<PurchaseReturnService>((ref) {
  return PurchaseReturnService(ref.watch(apiClientProvider));
});
