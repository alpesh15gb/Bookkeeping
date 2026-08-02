/// Vendor bill list provider — paginated list state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_bill.dart';
import '../services/vendor_bill_service.dart';

class BillListQuery {
  const BillListQuery({
    this.page = 1,
    this.limit = 50,
    this.search,
    this.status,
    this.contactId,
    this.dateFrom,
    this.dateTo,
  });
  final int page, limit;
  final String? search, status, contactId, dateFrom, dateTo;

  BillListQuery copyWith({
    int? page,
    int? limit,
    String? search,
    String? status,
    String? contactId,
    String? dateFrom,
    String? dateTo,
  }) => BillListQuery(
    page: page ?? this.page,
    limit: limit ?? this.limit,
    search: search ?? this.search,
    status: status ?? this.status,
    contactId: contactId ?? this.contactId,
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
  );
}

class BillListNotifier extends AutoDisposeAsyncNotifier<List<VendorBillListItem>> {
  BillListQuery _query = const BillListQuery();

  @override
  Future<List<VendorBillListItem>> build() async {
    final service = ref.watch(vendorBillServiceProvider);
    final result = await service.list(
      page: _query.page,
      limit: _query.limit,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
      _ => throw Exception('Unexpected result type'),
    };
  }

  Future<void> refresh() {
    _query = const BillListQuery();
    ref.invalidateSelf();
    return Future.value();
  }

  void goToPage(int page) {
    _query = _query.copyWith(page: page);
    ref.invalidateSelf();
  }

  void setFilters({
    String? search,
    String? status,
    String? contactId,
    String? dateFrom,
    String? dateTo,
  }) {
    _query = _query.copyWith(
      page: 1,
      search: search,
      status: status,
      contactId: contactId,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    ref.invalidateSelf();
  }
}

final billsListProvider = AutoDisposeAsyncNotifierProvider<BillListNotifier, List<VendorBillListItem>>(BillListNotifier.new);