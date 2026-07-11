/// Journal entry API service — CRUD + reversal.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/journal_entry.dart';

class JournalService {
  JournalService(this._dio);
  final Dio _dio;

  /// Create a manual journal entry.
  Future<Result<JournalEntry>> create(JournalEntry entry) async {
    try {
      final res = await _dio.post(
        '/accounting/journals',
        data: entry.toCreatePayload(),
      );
      return Success(JournalEntry.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// List journal entries with optional source_type filter.
  Future<Result<List<JournalEntry>>> list({
    int page = 1,
    int limit = 50,
    String? sourceType,
  }) async {
    try {
      final q = <String, dynamic>{'page': page, 'limit': limit};
      if (sourceType != null) q['source_type'] = sourceType;
      final res = await _dio.get('/accounting/journals', queryParameters: q);
      final items = (res.data as List)
          .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return Success(items);
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Get a single journal entry by ID.
  Future<Result<JournalEntry>> get(String id) async {
    try {
      final res = await _dio.get('/accounting/journals/$id');
      return Success(JournalEntry.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }

  /// Create a contra entry (transfer between accounts).
  Future<Result<JournalEntry>> createContra({
    required String entryDate,
    required String debitAccountId,
    required String creditAccountId,
    required double amount,
    String? description,
    String? referenceNumber,
  }) async {
    try {
      final data = <String, dynamic>{
        'entry_date': entryDate,
        'debit_account_id': debitAccountId,
        'credit_account_id': creditAccountId,
        'amount': amount,
        if (description != null) 'description': description,
        if (referenceNumber != null) 'reference_number': referenceNumber,
      };
      final res = await _dio.post('/accounting/contra', data: data);
      return Success(JournalEntry.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Failure(ApiError.network(e.message ?? ''));
    } catch (e) {
      return Failure(ApiError.network(e.toString()));
    }
  }
}

final journalServiceProvider = Provider<JournalService>((ref) {
  return JournalService(ref.watch(apiClientProvider));
});
