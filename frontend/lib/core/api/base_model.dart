/// Contract every CRUD model implements so [BaseRepository] can handle it
/// generically. Concrete models (Contact, Product, Account, ...) extend
/// [BaseModel] and provide [fromJson]/[toJson].
library;

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

export '../constants/app_constants.dart' show AppConstants;

/// A persistable record with a string (UUID) id and JSON (de)serialization.
@immutable
abstract class BaseModel {
  const BaseModel();

  /// The record's UUID (string form).
  String get id;

  /// Reconstructs the model from a JSON map.
  BaseModel fromJson(Map<String, dynamic> json);

  /// Serializes the model to a JSON map.
  Map<String, dynamic> toJson();
}

/// Sort direction for list queries.
enum SortDirection { ascending, descending }

extension SortDirectionX on SortDirection {
  String get wire => switch (this) {
    SortDirection.ascending => 'asc',
    SortDirection.descending => 'desc',
  };
}

/// Immutable description of a list query — mirrors the common query params
/// every ApexBooks paginated endpoint accepts (page, limit, search, status,
/// sort, plus arbitrary extra filters).
@immutable
class ListQuery {
  const ListQuery({
    this.page = 1,
    this.limit = AppConstants.defaultPageSize,
    this.search,
    this.status,
    this.sortBy,
    this.sortDirection = SortDirection.ascending,
    this.dateFrom,
    this.dateTo,
    this.extra = const {},
  });

  final int page;
  final int limit;
  final String? search;
  final String? status;
  final String? sortBy;
  final SortDirection sortDirection;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Extra filter params (e.g. `contact_type`, `product_type`, `contact_id`).
  final Map<String, dynamic> extra;

  /// Serializes the query to URL query parameters.
  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
      if (status != null && status!.isNotEmpty) 'status': status,
      if (sortBy != null && sortBy!.isNotEmpty) 'sort_by': sortBy,
      'sort_dir': sortDirection.wire,
      if (dateFrom != null) 'date_from': _fmtDate(dateFrom!),
      if (dateTo != null) 'date_to': _fmtDate(dateTo!),
      ...extra,
    };
    return params;
  }

  /// A stable cache key for this query.
  String cacheKey(String base) =>
      '$base:$page:$limit:${search ?? ''}:${status ?? ''}:${sortBy ?? ''}:'
      '${sortDirection.wire}:${dateFrom?.toIso8601String() ?? ''}:'
      '${dateTo?.toIso8601String() ?? ''}:${extra.toString()}';

  /// Returns a copy with overridden fields (used for pagination/sort changes).
  ListQuery copyWith({
    int? page,
    int? limit,
    String? search,
    String? status,
    String? sortBy,
    SortDirection? sortDirection,
    DateTime? dateFrom,
    DateTime? dateTo,
    Map<String, dynamic>? extra,
    bool clearSearch = false,
    bool clearStatus = false,
    bool clearDateRange = false,
  }) {
    return ListQuery(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      search: clearSearch ? null : (search ?? this.search),
      status: clearStatus ? null : (status ?? this.status),
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      extra: extra ?? this.extra,
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
