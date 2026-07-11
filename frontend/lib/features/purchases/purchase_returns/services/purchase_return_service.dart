/// Purchase return API service.
///
/// Per the posting contract: Return posting must invoke
/// InventoryPostingService (stock-out reversal) and
/// PayablePostingService (reduce vendor payable / create debit note).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_return.dart';

class PurchaseReturnService {
  PurchaseReturnService(this._dio);
  final Dio _dio;

  Future<Result<PurchaseReturn>> create(PurchaseReturn ret) async {
    try {
      final res = await _dio.post(
        '/purchase-returns',
        data: ret.toCreatePayload(),
      );
      return Success(PurchaseReturn.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<PurchaseReturnListItem>>> list({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/purchase-returns',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map(
            (e) => PurchaseReturnListItem.fromJson(e as Map<String, dynamic>),
          )
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<PurchaseReturn>> get(String id) async {
    try {
      final res = await _dio.get('/purchase-returns/$id');
      return Success(PurchaseReturn.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Post a draft return — triggers stock-out reversal + payable adjustment.
  Future<Result<PurchaseReturn>> post(String id) async {
    try {
      final res = await _dio.post('/purchase-returns/$id/post');
      return Success(PurchaseReturn.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<PurchaseReturn>> cancel(String id) async {
    try {
      final res = await _dio.post('/purchase-returns/$id/cancel');
      return Success(PurchaseReturn.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final purchaseReturnServiceProvider = Provider<PurchaseReturnService>((ref) {
  return PurchaseReturnService(ref.watch(apiClientProvider));
});
