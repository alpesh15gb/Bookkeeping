/// Vendor payment API service.
///
/// Per the posting contract: Payment confirmation must invoke
/// LedgerPostingService and PayablePostingService.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_payment.dart';
import '../models/outstanding_bill.dart';

class VendorPaymentService {
  VendorPaymentService(this._dio);
  final Dio _dio;

  Future<Result<VendorPayment>> create(VendorPayment payment) async {
    try {
      final res = await _dio.post(
        '/bills/payments',
        data: payment.toCreatePayload(),
      );
      return Success(VendorPayment.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<VendorPayment>>> list({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/bills/payments',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map((e) => VendorPayment.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<VendorPayment>> cancel(String id) async {
    try {
      final res = await _dio.post('/bills/payments/$id/cancel');
      return Success(VendorPayment.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Fetch outstanding bills for a vendor (for allocation selection).
  Future<Result<List<OutstandingBill>>> outstandingBills(
    String contactId,
  ) async {
    try {
      final res = await _dio.get('/contacts/$contactId/outstanding-bills');
      final items = (res.data as List)
          .map((e) => OutstandingBill.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final vendorPaymentServiceProvider = Provider<VendorPaymentService>((ref) {
  return VendorPaymentService(ref.watch(apiClientProvider));
});
