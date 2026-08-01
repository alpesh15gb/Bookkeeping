/// Bank reconciliation API service.
///
/// Supports statement import, auto matching, manual matching, undo.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/reconciliation_models.dart';

class ReconciliationService {
  ReconciliationService(this._dio);
  final Dio _dio;

  Future<Result<List<BankReconciliationListItem>>> list({
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/bank-reconciliation/reconciliations',
        queryParameters: {'page': page, 'limit': limit},
      );
      return (res.data as List)
          .map(
            (e) =>
                BankReconciliationListItem.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<Result<BankReconciliation>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/bank-reconciliation/reconciliations/$id');
      return BankReconciliation.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<BankReconciliation>> uploadStatement({
    required String bankingProfileId,
    required String filePath,
  }) {
    return guardDio(() async {
      final formData = FormData.fromMap({
        'banking_profile_id': bankingProfileId,
        'file': await MultipartFile.fromFile(filePath),
      });
      final res = await _dio.post(
        '/bank-reconciliation/upload',
        data: formData,
      );
      return BankReconciliation.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<BankReconciliation>> reconcileTransaction({
    required String transactionId,
    required String journalEntryId,
  }) {
    return guardDio(() async {
      final res = await _dio.post(
        '/bank-reconciliation/transactions/$transactionId/reconcile',
        data: {'journal_entry_id': journalEntryId},
      );
      return BankReconciliation.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<BankReconciliation>> bulkReconcile({
    required String reconciliationId,
    required List<Map<String, dynamic>> matches,
  }) {
    return guardDio(() async {
      final res = await _dio.post(
        '/bank-reconciliation/bulk-reconcile',
        data: {'reconciliation_id': reconciliationId, 'matches': matches},
      );
      return BankReconciliation.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<BankReconciliation>> undo(String id) {
    return guardDio(() async {
      final res = await _dio.post(
        '/bank-reconciliation/reconciliations/$id/undo',
      );
      return BankReconciliation.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<MatchSuggestion>>> getSuggestions(String statementId) {
    return guardDio(() async {
      final res = await _dio.get(
        '/bank-reconciliation/statements/$statementId/suggestions',
      );
      return (res.data as List)
          .map((e) => MatchSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}

final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  return ReconciliationService(ref.watch(apiClientProvider));
});
