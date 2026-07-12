/// Reactive table state: pagination, sort, multi-filter, search, selection
/// and column visibility. Drives [ApexDataTable] and is owned by the
/// feature's controller (which calls the repository with the derived
/// [ListQuery] whenever state changes).
library;

import 'package:flutter/foundation.dart';

import '../api/base_model.dart';
import 'table_column.dart';

/// Immutable snapshot of a table's interactive state.
@immutable
class ApexTableState {
  const ApexTableState({
    this.page = 1,
    this.limit = 20,
    this.search = '',
    this.sort = const TableSort(),
    this.statusFilter,
    this.activeFilters = const {},
    this.dateFrom,
    this.dateTo,
    this.selectedIds = const {},
    this.hiddenColumns = const {},
  });

  final int page;
  final int limit;
  final String search;
  final TableSort sort;
  final String? statusFilter;
  final Map<String, String> activeFilters;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Set<String> selectedIds;
  final Set<String> hiddenColumns;

  bool get hasActiveFilters =>
      (statusFilter != null && statusFilter!.isNotEmpty) ||
      activeFilters.isNotEmpty ||
      dateFrom != null ||
      dateTo != null ||
      search.trim().isNotEmpty;

  ApexTableState copyWith({
    int? page,
    int? limit,
    String? search,
    TableSort? sort,
    Object? statusFilter,
    Map<String, String>? activeFilters,
    DateTime? dateFrom,
    DateTime? dateTo,
    Set<String>? selectedIds,
    Set<String>? hiddenColumns,
    bool clearStatus = false,
    bool clearDateRange = false,
  }) {
    return ApexTableState(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      search: search ?? this.search,
      sort: sort ?? this.sort,
      statusFilter: clearStatus
          ? null
          : (statusFilter as String?) ?? this.statusFilter,
      activeFilters: activeFilters ?? this.activeFilters,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      selectedIds: selectedIds ?? this.selectedIds,
      hiddenColumns: hiddenColumns ?? this.hiddenColumns,
    );
  }
}

/// Controller that mutates [ApexTableState] and notifies listeners. The
/// owning feature controller listens and re-fetches via its repository.
class ApexTableController extends ValueNotifier<ApexTableState> {
  ApexTableController() : super(const ApexTableState());

  void setPage(int p) => value = value.copyWith(page: p);
  void setLimit(int l) => value = value.copyWith(page: 1, limit: l);
  void setSearch(String s) => value = value.copyWith(page: 1, search: s);
  void setStatusFilter(String? s) =>
      value = value.copyWith(page: 1, statusFilter: s);
  void setFilter(String key, String? val) {
    final filters = Map<String, String>.from(value.activeFilters);
    if (val == null || val.isEmpty) {
      filters.remove(key);
    } else {
      filters[key] = val;
    }
    value = value.copyWith(page: 1, activeFilters: filters);
  }

  void setDateRange(DateTime? from, DateTime? to) =>
      value = value.copyWith(page: 1, dateFrom: from, dateTo: to);

  /// Toggles sort on [columnId]; clicking the same column flips direction.
  void toggleSort(String columnId) {
    final current = value.sort;
    if (current.columnId == columnId) {
      value = value.copyWith(
        sort: current.copyWith(
          direction: current.direction == SortDirection.ascending
              ? SortDirection.descending
              : SortDirection.ascending,
        ),
      );
    } else {
      value = value.copyWith(
        sort: TableSort(columnId: columnId, direction: SortDirection.ascending),
      );
    }
  }

  void toggleColumnVisibility(String columnId) {
    final hidden = Set<String>.from(value.hiddenColumns);
    if (!hidden.add(columnId)) hidden.remove(columnId);
    value = value.copyWith(hiddenColumns: hidden);
  }

  void toggleSelection(String id) {
    final selected = Set<String>.from(value.selectedIds);
    if (!selected.add(id)) selected.remove(id);
    value = value.copyWith(selectedIds: selected);
  }

  void selectAll(Iterable<String> ids) =>
      value = value.copyWith(selectedIds: ids.toSet());

  void clearSelection() => value = value.copyWith(selectedIds: const {});

  void clearFilters() => value = const ApexTableState();

  /// Builds the [ListQuery] derived from the current state, ready to pass to
  /// a [BaseRepository.list] call.
  ListQuery toListQuery() => ListQuery(
    page: value.page,
    limit: value.limit,
    search: value.search.trim().isEmpty ? null : value.search.trim(),
    status: value.statusFilter,
    sortBy: value.sort.sortBy,
    sortDirection: value.sort.direction,
    dateFrom: value.dateFrom,
    dateTo: value.dateTo,
    extra: value.activeFilters,
  );
}
