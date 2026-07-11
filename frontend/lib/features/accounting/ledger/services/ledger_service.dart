/// Ledger API service — reads from posted journal entries via backend.
///
/// Per the architecture rule: Everything reads from posted journals.
/// No independent balances.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/ledger_report.dart';

class LedgerService {
  LedgerService(this._dio);
  final Dio _dio;

  /// Get the general ledger statement for a specific account.
  Future<Result<LedgerReport>> getAccountLedger({
    required String accountId,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final q = <String, dynamic>{'page': page, 'limit': limit};
      if (fromDate != null) q['from_date'] = fromDate;
      if (toDate != null) q['to_date'] = toDate;
      final res = await _dio.get(
        '/accounting/ledger/$accountId',
        queryParameters: q,
      );
      return Success(LedgerReport.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService(ref.watch(apiClientProvider));
});
