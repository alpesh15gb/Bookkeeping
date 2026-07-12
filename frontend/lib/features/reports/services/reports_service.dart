/// Reports API service — calls backend endpoints for the reports hub.
///
/// Provides access to sales transactions, bills, party statements, and
/// contact search. Follows the same guardDio + Result pattern as the
/// financial statement services.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/report_models.dart';

class ReportsService {
  ReportsService(this._dio);
  final Dio _dio;

  /// GET /sales/transactions — paginated finalized sales.
  Future<Result<List<SalesTransaction>>> getSalesTransactions({
    String? dateFrom,
    String? dateTo,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (dateFrom != null) q['date_from'] = dateFrom;
      if (dateTo != null) q['date_to'] = dateTo;
      final res = await _dio.get('/sales/transactions', queryParameters: q);
      final list = res.data as List;
      return list
          .map((e) => SalesTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// GET /bills — paginated bills with optional date / vendor filters.
  Future<Result<List<PurchaseTransaction>>> getBills({
    String? dateFrom,
    String? dateTo,
    String? contactId,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (dateFrom != null) q['date_from'] = dateFrom;
      if (dateTo != null) q['date_to'] = dateTo;
      if (contactId != null) q['contact_id'] = contactId;
      final res = await _dio.get('/bills', queryParameters: q);
      final data = res.data as Map<String, dynamic>;
      final items = data['items'] as List? ?? [];
      return items
          .map((e) => PurchaseTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// GET /reports/party-statement — ledger for a single customer/vendor.
  Future<Result<PartyStatement>> getPartyStatement({
    required String contactId,
    required String startDate,
    required String endDate,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/reports/party-statement',
        queryParameters: {
          'contact_id': contactId,
          'start_date': startDate,
          'end_date': endDate,
        },
      );
      return PartyStatement.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// GET /masters/contacts — search contacts for autocomplete selectors.
  Future<Result<List<ContactSummary>>> getContacts({
    String? contactType,
    String? search,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (contactType != null) q['contact_type'] = contactType;
      if (search != null) q['search'] = search;
      final res = await _dio.get('/masters/contacts', queryParameters: q);
      final list = res.data as List;
      return list
          .map((e) => ContactSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}

final reportsServiceProvider = Provider<ReportsService>((ref) {
  return ReportsService(ref.watch(apiClientProvider));
});
