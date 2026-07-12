/// Trial Balance API service — generates entirely from journals.
///
/// Per the architecture rule: Trial Balance is generated entirely from posted
/// journals. If it doesn't balance, fail loudly.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/trial_balance.dart';

class TrialBalanceService {
  TrialBalanceService(this._dio);
  final Dio _dio;

  Future<Result<TrialBalanceReport>> getTrialBalance({String? asOfDate}) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (asOfDate != null) q['as_of_date'] = asOfDate;
      final res = await _dio.get(
        '/accounting/trial-balance',
        queryParameters: q,
      );
      return TrialBalanceReport.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final trialBalanceServiceProvider = Provider<TrialBalanceService>((ref) {
  return TrialBalanceService(ref.watch(apiClientProvider));
});
