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
        '/payments/disbursements',
        data: payment.toCreatePayload(),
      );
      return VendorPayment.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<VendorPayment>>> list({int page = 1, int limit = 50}) {
    return guardDio(() async {
      final res = await _dio.get(
        '/payments/disbursements',
        queryParameters: {'page': page, 'limit': limit},
      );
      return (res.data as List)
          .whereType<Map>()
          .map((e) => VendorPayment.fromJson(e.cast<String, dynamic>()))
          .toList();
    });
  }

  Future<Result<VendorPayment>> cancel(String id) {
    return guardDio(() async {
      final res = await _dio.post(
        '/payments/disbursements/$id/cancel',
        data: {'reason': 'Cancelled by user'},
      );
      return VendorPayment.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<OutstandingBill>>> outstandingBills(String contactId) {
    return guardDio(() async {
      final res = await _dio.get(
        '/payments/disbursements/outstanding/$contactId',
      );
      final rows = res.data;
      if (rows is! List) {
        throw const FormatException('Invalid outstanding bill response.');
      }
      return rows
          .whereType<Map>()
          .map((e) => OutstandingBill.fromJson(e.cast<String, dynamic>()))
          .toList();
    });
  }
}

final vendorPaymentServiceProvider = Provider<VendorPaymentService>((ref) {
  return VendorPaymentService(ref.watch(apiClientProvider));
});
