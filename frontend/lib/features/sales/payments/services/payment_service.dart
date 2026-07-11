/// Payment API service — all backend calls for receipts (AR).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/payment_models.dart';

class PaymentService {
  PaymentService(this._dio);
  final Dio _dio;

  // -- Helpers -------------------------------------------------------------

  Future<Result<Payment>> _getPayment(String path) async {
    try {
      return Success(
        Payment.fromJson((await _dio.get(path)).data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  // -- CRUD -----------------------------------------------------------------

  /// Create a payment receipt with allocations.
  Future<Result<Payment>> create(Map<String, dynamic> payload) async {
    try {
      return Success(
        Payment.fromJson(
          (await _dio.post('/payments/receipts', data: payload)).data
              as Map<String, dynamic>,
        ),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// List payment receipts (paginated, optional contact filter).
  Future<Result<List<PaymentListItem>>> list({
    int page = 1,
    int limit = 50,
    String? contactId,
  }) async {
    try {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (contactId != null) 'contact_id': contactId,
      };
      final res = await _dio.get('/payments/receipts', queryParameters: q);
      final items = (res.data as List)
          .map((e) => PaymentListItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get a single payment receipt with allocations.
  Future<Result<Payment>> get(String id) =>
      _getPayment('/payments/receipts/$id');

  /// Cancel a payment receipt (reverses allocations & ledger).
  Future<Result<Payment>> cancel(String id) async {
    try {
      return Success(
        Payment.fromJson(
          (await _dio.post('/payments/receipts/$id/cancel')).data
              as Map<String, dynamic>,
        ),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(apiClientProvider));
});
