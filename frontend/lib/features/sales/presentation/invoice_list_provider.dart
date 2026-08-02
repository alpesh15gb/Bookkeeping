/// Invoice list provider — paginated list state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/invoice.dart';
import '../services/invoice_service.dart';
import 'components/invoice_filter_bar.dart' show InvoiceFilter;

class InvoiceListQuery {
  const InvoiceListQuery({
    this.page = 1,
    this.limit = 20,
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

class InvoiceListNotifier extends AutoDisposeAsyncNotifier<({List<InvoiceListItem> items, int total})> {
  InvoiceListQuery _query = const InvoiceListQuery();

  @override
  Future<({List<InvoiceListItem> items, int total})> build() async {
    final service = ref.watch(invoiceServiceProvider);
    final result = await service.list(
      page: _query.page,
      limit: _query.limit,
      search: _query.search,
      status: _query.status,
      contactId: _query.contactId,
      dateFrom: _query.dateFrom,
      dateTo: _query.dateTo,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
      _ => throw Exception('Unexpected result type'),
    };
  }

  Future<void> refresh() {
    _query = const InvoiceListQuery();
    ref.invalidateSelf();
    return Future.value();
  }

  void goToPage(int page) {
    _query = _query.copyWith(page: page);
    ref.invalidateSelf();
  }

  void setFilters(InvoiceFilter filter) {
    _query = _query.copyWith(
      page: 1,
      search: filter.searchQuery,
      status: filter.status?.value,
      contactId: filter.customerQuery,
      dateFrom: filter.dateFrom?.toIso8601String(),
      dateTo: filter.dateTo?.toIso8601String(),
    );
    ref.invalidateSelf();
  }
}

final invoiceListProvider = AutoDisposeAsyncNotifierProvider<InvoiceListNotifier, ({List<InvoiceListItem> items, int total})>(InvoiceListNotifier.new);