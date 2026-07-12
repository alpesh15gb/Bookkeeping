/// Vendor payment API service.
///
/// Per the posting contract: Payment confirmation must invoke
/// LedgerPostingService and PayablePostingService.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_payment.dart';
import '../models/outstanding_bill.dart';

class VendorPaymentService {
  VendorPaymentService(this._dio);
  final Dio _dio;

  Future<Result<VendorPayment>> create(VendorPayment payment) {
    return guardDio(() async {
      final res = await _dio.post(
        '/bills/payments',
        data: payment.toCreatePayload(),
      );
      return VendorPayment.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<VendorPayment>>> list({
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/bills/payments',
        queryParameters: {'page': page, 'limit': limit},
      );
      return (res.data as List)
          .map((e) => VendorPayment.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<VendorPayment>> cancel(String id) {
    return guardDio(() async {
      final res = await _dio.post('/bills/payments/$id/cancel');
      return VendorPayment.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<OutstandingBill>>> outstandingBills(String contactId) {
    return guardDio(() async {
      final res = await _dio.get('/contacts/$contactId/outstanding-bills');
      return (res.data as List)
          .map((e) => OutstandingBill.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}

final vendorPaymentServiceProvider = Provider<VendorPaymentService>((ref) {
  return VendorPaymentService(ref.watch(apiClientProvider));
});
