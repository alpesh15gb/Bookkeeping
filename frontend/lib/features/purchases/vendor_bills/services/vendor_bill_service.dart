/// Vendor bill API service.
///
/// Per the posting contract: Bill finalization must invoke
/// LedgerPostingService, GSTPostingService, and PayablePostingService.
/// This service provides the API layer; posting is orchestrated by the controller.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_bill.dart';

class VendorBillService {
  VendorBillService(this._dio);
  final Dio _dio;

  Future<Result<VendorBill>> create(VendorBill bill) {
    return guardDio(() async {
      final res = await _dio.post('/bills', data: bill.toCreatePayload());
      return VendorBill.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<VendorBillListItem>>> list({
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/bills',
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = res.data;
      final rows = data is Map ? data['items'] : data;
      if (rows is! List) {
        throw const FormatException('Invalid bill list response.');
      }
      return rows
          .whereType<Map<Object?, Object?>>()
          .map((e) => VendorBillListItem.fromJson(e.cast<String, dynamic>()))
          .toList();
    });
  }

  Future<Result<VendorBill>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/bills/$id');
      return VendorBill.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Finalize/post a draft bill — triggers ledger + GST + payable posting.
  Future<Result<VendorBill>> post(String id) {
    return guardDio(() async {
      final res = await _dio.post('/bills/$id/post');
      return VendorBill.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Cancel a posted bill — reverses ledger postings.
  Future<Result<VendorBill>> cancel(String id) {
    return guardDio(() async {
      final res = await _dio.post('/bills/$id/cancel');
      return VendorBill.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Delete a draft bill.
  Future<Result<void>> delete(String id) {
    return guardDio(() async {
      await _dio.delete('/bills/$id');
    });
  }

  /// Returns the /print path for downloading PDF from the backend.
  String getPdfUrl(String id) => '/bills/$id/print';
}

final vendorBillServiceProvider = Provider<VendorBillService>((ref) {
  return VendorBillService(ref.watch(apiClientProvider));
});
