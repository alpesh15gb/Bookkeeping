/// Journal entry API service — CRUD + reversal.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/journal_entry.dart';

class JournalService {
  JournalService(this._dio);
  final Dio _dio;

  Future<Result<JournalEntry>> create(JournalEntry entry) {
    return guardDio(() async {
      final res = await _dio.post(
        '/accounting/journals',
        data: entry.toCreatePayload(),
      );
      return JournalEntry.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<List<JournalEntry>>> list({
    int page = 1,
    int limit = 50,
    String? sourceType,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{'page': page, 'limit': limit};
      if (sourceType != null) q['source_type'] = sourceType;
      final res = await _dio.get('/accounting/journals', queryParameters: q);
      return (res.data as List)
          .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<JournalEntry>> get(String id) {
    return guardDio(() async {
      final res = await _dio.get('/accounting/journals/$id');
      return JournalEntry.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<Result<JournalEntry>> createContra({
    required String entryDate,
    required String debitAccountId,
    required String creditAccountId,
    required double amount,
    String? description,
    String? referenceNumber,
  }) {
    return guardDio(() async {
      final data = <String, dynamic>{
        'entry_date': entryDate,
        'debit_account_id': debitAccountId,
        'credit_account_id': creditAccountId,
        'amount': amount,
        if (description != null) 'description': description,
        if (referenceNumber != null) 'reference_number': referenceNumber,
      };
      final res = await _dio.post('/accounting/contra', data: data);
      return JournalEntry.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final journalServiceProvider = Provider<JournalService>((ref) {
  return JournalService(ref.watch(apiClientProvider));
});
