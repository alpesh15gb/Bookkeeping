/// Vendor bill API service.
///
/// Per the posting contract: Bill finalization must invoke
/// LedgerPostingService, GSTPostingService, and PayablePostingService.
/// This service provides the API layer; posting is orchestrated by the controller.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_bill.dart';

class VendorBillService {
  VendorBillService(this._dio);
  final Dio _dio;

  Future<Result<VendorBill>> create(VendorBill bill) async {
    try {
      final res = await _dio.post('/bills', data: bill.toCreatePayload());
      return Success(VendorBill.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<VendorBillListItem>>> list({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/bills',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map((e) => VendorBillListItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<VendorBill>> get(String id) async {
    try {
      final res = await _dio.get('/bills/$id');
      return Success(VendorBill.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Finalize/post a draft bill — triggers ledger + GST + payable posting.
  Future<Result<VendorBill>> post(String id) async {
    try {
      final res = await _dio.post('/bills/$id/post');
      return Success(VendorBill.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Cancel a posted bill — reverses ledger postings.
  Future<Result<VendorBill>> cancel(String id) async {
    try {
      final res = await _dio.post('/bills/$id/cancel');
      return Success(VendorBill.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final vendorBillServiceProvider = Provider<VendorBillService>((ref) {
  return VendorBillService(ref.watch(apiClientProvider));
});
