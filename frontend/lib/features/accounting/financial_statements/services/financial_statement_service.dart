/// Financial Statement API service — reads entirely from ledger.
///
/// Per the architecture rule: Never compute totals independently inside reports.
/// Everything derives from the ledger via the backend.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/profit_loss.dart';
import '../models/balance_sheet.dart';

class FinancialStatementService {
  FinancialStatementService(this._dio);
  final Dio _dio;

  /// Get Profit & Loss report for a date range.
  Future<Result<ProfitLossReport>> getProfitLoss({
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final q = <String, dynamic>{};
      if (dateFrom != null) q['date_from'] = dateFrom;
      if (dateTo != null) q['date_to'] = dateTo;
      final res = await _dio.get('/accounting/profit-loss', queryParameters: q);
      return Success(
        ProfitLossReport.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get Balance Sheet as of a date.
  Future<Result<BalanceSheetReport>> getBalanceSheet({String? asOnDate}) async {
    try {
      final q = <String, dynamic>{};
      if (asOnDate != null) q['as_on_date'] = asOnDate;
      final res = await _dio.get(
        '/accounting/balance-sheet',
        queryParameters: q,
      );
      return Success(
        BalanceSheetReport.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get cash and bank balances.
  Future<Result<Map<String, double>>> getCashBankBalances() async {
    try {
      final res = await _dio.get('/accounting/cash-bank-balances');
      final data = res.data as Map<String, dynamic>;
      return Success(data.map((k, v) => MapEntry(k, _num(v))));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

final financialStatementServiceProvider = Provider<FinancialStatementService>((
  ref,
) {
  return FinancialStatementService(ref.watch(apiClientProvider));
});
