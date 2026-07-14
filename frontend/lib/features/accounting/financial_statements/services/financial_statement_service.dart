/// Financial Statement API service — reads entirely from ledger.
///
/// Per the architecture rule: Never compute totals independently inside reports.
/// Everything derives from the ledger via the backend.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/profit_loss.dart';
import '../models/balance_sheet.dart';
import '../models/cash_book.dart';
import '../models/day_book.dart';

class FinancialStatementService {
  FinancialStatementService(this._dio);
  final Dio _dio;

  Future<Result<ProfitLossReport>> getProfitLoss({
    String? dateFrom,
    String? dateTo,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (dateFrom != null) q['date_from'] = dateFrom;
      if (dateTo != null) q['date_to'] = dateTo;
      final res = await _dio.get('/accounting/profit-loss', queryParameters: q);
      return ProfitLossReport.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<BalanceSheetReport>> getBalanceSheet({String? asOnDate}) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (asOnDate != null) q['as_on_date'] = asOnDate;
      final res = await _dio.get(
        '/accounting/balance-sheet',
        queryParameters: q,
      );
      return BalanceSheetReport.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<CashBookReport>> getCashBook({
    String? startDate,
    String? endDate,
  }) {
    return guardDio(() async {
      final q = _requiredPeriod(startDate, endDate);
      final res = await _dio.get('/reports/cash-book', queryParameters: q);
      return CashBookReport.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<CashBookReport>> getBankBook({
    String? startDate,
    String? endDate,
  }) {
    return guardDio(() async {
      final q = _requiredPeriod(startDate, endDate);
      final res = await _dio.get('/reports/bank-book', queryParameters: q);
      return CashBookReport.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<DayBookReport>> getDayBook({
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 50,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{
        ..._requiredPeriod(startDate, endDate),
        'page': page,
        'limit': limit.clamp(1, 100),
      };
      final res = await _dio.get('/reports/day-book', queryParameters: q);
      return DayBookReport.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<Map<String, double>>> getCashBankBalances() {
    return guardDio(() async {
      final res = await _dio.get('/accounting/cash-bank-balances');
      final data = res.data as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, _num(v)));
    });
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Cash, bank, and day-book endpoints require both dates. Providers are
  /// evaluated before a screen's initState callback, so the service must also
  /// supply a deterministic initial period instead of issuing an invalid call.
  static Map<String, dynamic> _requiredPeriod(String? start, String? end) {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    String format(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return {
      'start_date': start ?? format(firstDay),
      'end_date': end ?? format(now),
    };
  }
}

final financialStatementServiceProvider = Provider<FinancialStatementService>((
  ref,
) {
  return FinancialStatementService(ref.watch(apiClientProvider));
});
