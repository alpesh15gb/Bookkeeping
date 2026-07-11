/// Invoice list provider — paginated list state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/invoice.dart';
import '../services/invoice_service.dart';

class InvoiceListQuery {
  const InvoiceListQuery({
    this.page = 1,
    this.limit = 25,
    this.search,
    this.status,
    this.contactId,
    this.dateFrom,
    this.dateTo,
  });
  final int page, limit;
  final String? search, status, contactId, dateFrom, dateTo;

  InvoiceListQuery copyWith({
    int? page,
    int? limit,
    String? search,
    String? status,
    String? contactId,
    String? dateFrom,
    String? dateTo,
  }) => InvoiceListQuery(
    page: page ?? this.page,
    limit: limit ?? this.limit,
    search: search ?? this.search,
    status: status ?? this.status,
    contactId: contactId ?? this.contactId,
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
  );
}

final invoiceListProvider = FutureProvider.autoDispose
    .family<({List<InvoiceListItem> items, int total}), InvoiceListQuery>((
      ref,
      query,
    ) async {
      final service = ref.watch(invoiceServiceProvider);
      final result = await service.list(
        page: query.page,
        limit: query.limit,
        search: query.search,
        status: query.status,
        contactId: query.contactId,
        dateFrom: query.dateFrom,
        dateTo: query.dateTo,
      );
      return switch (result) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception('Unexpected result type'),
      };
    });
