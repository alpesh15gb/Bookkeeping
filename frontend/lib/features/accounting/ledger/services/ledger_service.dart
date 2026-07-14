/// Ledger API service — reads from posted journal entries via backend.
///
/// Per the architecture rule: Everything reads from posted journals.
/// No independent balances.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/ledger_report.dart';

class LedgerService {
  LedgerService(this._dio);
  final Dio _dio;

  Future<Result<LedgerReport>> getAccountLedger({
    required String accountId,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 100,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{'page': page, 'limit': limit.clamp(1, 100)};
      if (fromDate != null) q['from_date'] = fromDate;
      if (toDate != null) q['to_date'] = toDate;
      final res = await _dio.get(
        '/accounting/ledger/$accountId',
        queryParameters: q,
      );
      return LedgerReport.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService(ref.watch(apiClientProvider));
});
