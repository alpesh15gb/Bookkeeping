/// Financial Year API service — manage FY lifecycle.
///
/// Per the architecture rule: Year-end closing should generate opening balances
/// for the next year through journal postings, not by mutating balances.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/financial_year.dart';
import '../models/year_end_dashboard.dart';

class FinancialYearService {
  FinancialYearService(this._dio);
  final Dio _dio;

  Future<Result<List<FinancialYear>>> list() async {
    try {
      final res = await _dio.get('/financial-years');
      final items = (res.data as List)
          .map((e) => FinancialYear.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<FinancialYear>> create({
    required String name,
    required String startDate,
    required String endDate,
  }) async {
    try {
      final data = <String, dynamic>{
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
      };
      final res = await _dio.post('/financial-years', data: data);
      return Success(FinancialYear.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<FinancialYear>> getCurrent() async {
    try {
      final res = await _dio.get('/financial-years/current');
      return Success(FinancialYear.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<FinancialYear>> switchYear(String fyId) async {
    try {
      final res = await _dio.post(
        '/financial-years/switch',
        data: {'financial_year_id': fyId},
      );
      return Success(FinancialYear.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<YearEndDashboard>> getDashboard(String fyId) async {
    try {
      final res = await _dio.get('/financial-years/$fyId/dashboard');
      return Success(
        YearEndDashboard.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<FinancialYear>> close({
    required String fyId,
    required String closingDate,
  }) async {
    try {
      final res = await _dio.post(
        '/financial-years/$fyId/close',
        data: {'closing_date': closingDate},
      );
      return Success(FinancialYear.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<FinancialYear>> reopen({
    required String fyId,
    required String reason,
  }) async {
    try {
      final res = await _dio.post(
        '/financial-years/$fyId/reopen',
        data: {'reason': reason},
      );
      return Success(FinancialYear.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<OpeningBalanceSnapshot>>> getOpeningBalances(
    String fyId,
  ) async {
    try {
      final res = await _dio.get('/financial-years/$fyId/opening-balances');
      final items = (res.data as List)
          .map(
            (e) => OpeningBalanceSnapshot.fromJson(e as Map<String, dynamic>),
          )
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<List<InventoryCarryForward>>> getInventoryCarryForward(
    String fyId,
  ) async {
    try {
      final res = await _dio.get(
        '/financial-years/$fyId/inventory-carry-forward',
      );
      final items = (res.data as List)
          .map((e) => InventoryCarryForward.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  Future<Result<void>> updateOpeningBalances({
    required String fyId,
    required List<Map<String, dynamic>> balances,
  }) async {
    try {
      await _dio.post(
        '/accounting/opening-balances',
        data: {'financial_year_id': fyId, 'balances': balances},
      );
      return const Success(null);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final financialYearServiceProvider = Provider<FinancialYearService>((ref) {
  return FinancialYearService(ref.watch(apiClientProvider));
});
