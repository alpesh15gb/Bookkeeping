/// Bank reconciliation API service.
///
/// Supports statement import, auto matching, manual matching, undo.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/reconciliation_models.dart';

class ReconciliationService {
  ReconciliationService(this._dio);
  final Dio _dio;

  /// List bank reconciliations.
  Future<Result<List<BankReconciliationListItem>>> list({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        '/bank-reconciliation/reconciliations',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (res.data as List)
          .map(
            (e) =>
                BankReconciliationListItem.fromJson(e as Map<String, dynamic>),
          )
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get a single reconciliation by ID.
  Future<Result<BankReconciliation>> get(String id) async {
    try {
      final res = await _dio.get('/bank-reconciliation/reconciliations/$id');
      return Success(
        BankReconciliation.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Upload a bank statement for reconciliation.
  Future<Result<BankReconciliation>> uploadStatement({
    required String bankingProfileId,
    required String filePath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'banking_profile_id': bankingProfileId,
        'file': await MultipartFile.fromFile(filePath),
      });
      final res = await _dio.post(
        '/bank-reconciliation/upload',
        data: formData,
      );
      return Success(
        BankReconciliation.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Manually reconcile a single bank transaction.
  Future<Result<BankReconciliation>> reconcileTransaction({
    required String transactionId,
    required String journalEntryId,
  }) async {
    try {
      final res = await _dio.post(
        '/bank-reconciliation/transactions/$transactionId/reconcile',
        data: {'journal_entry_id': journalEntryId},
      );
      return Success(
        BankReconciliation.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Bulk reconcile multiple transactions.
  Future<Result<BankReconciliation>> bulkReconcile({
    required String reconciliationId,
    required List<Map<String, dynamic>> matches,
  }) async {
    try {
      final res = await _dio.post(
        '/bank-reconciliation/bulk-reconcile',
        data: {'reconciliation_id': reconciliationId, 'matches': matches},
      );
      return Success(
        BankReconciliation.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Undo a reconciliation.
  Future<Result<BankReconciliation>> undo(String id) async {
    try {
      final res = await _dio.post(
        '/bank-reconciliation/reconciliations/$id/undo',
      );
      return Success(
        BankReconciliation.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  return ReconciliationService(ref.watch(apiClientProvider));
});
