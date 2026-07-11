/// Convenience extension that turns Dio calls into typed [Result]s and maps
/// every failure into [ApiError].
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../result/result.dart';
import 'error_mapper.dart';

/// Wraps an async Dio call so failures are normalized into [Failure] and
/// successes into [Success].
Future<Result<T>> guardDio<T>(Future<T> Function() call) async {
  try {
    final value = await call();
    return Success(value);
  } on DioException catch (err) {
    return Failure(toApiError(err));
  } on ApiError catch (err) {
    return Failure(err);
  } catch (err) {
    return Failure(ApiError.network(err.toString()));
  }
}

/// Parses a paginated list response `{items, total, page, limit}` into a
/// typed [Paged] snapshot.
@immutable
class Paged<T> {
  const Paged({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<T> items;
  final int total;
  final int page;
  final int limit;

  int get totalPages => limit <= 0 ? 1 : (total / limit).ceil();
  bool get hasMore => page < totalPages;
}

/// Extracts a paginated payload, mapping each item with [fromJson].
///
/// Accepts either:
///   * an envelope `{items, total, page, limit}` (preferred), or
///   * a flat JSON array `[ {...}, {...} ]` (as returned by the ApexBooks
///     masters endpoints, e.g. `GET /masters/contacts` → `List[ContactResponse]`).
/// For a flat array the total/page/limit are derived from the array length and
/// the query that produced it.
Paged<T> parsePaged<T>(
  Object? data,
  T Function(Map<String, dynamic>) fromJson, {
  int page = 1,
  int limit = 20,
}) {
  final items = <T>[];
  int total = items.length;
  int resolvedPage = page;
  int resolvedLimit = limit;

  if (data is Map<String, dynamic>) {
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(fromJson(item));
        } else if (item is Map) {
          items.add(fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    total = (data['total'] as num?)?.toInt() ?? items.length;
    resolvedPage = (data['page'] as num?)?.toInt() ?? page;
    resolvedLimit = (data['limit'] as num?)?.toInt() ?? limit;
  } else if (data is List) {
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        items.add(fromJson(item));
      } else if (item is Map) {
        items.add(fromJson(item.cast<String, dynamic>()));
      }
    }
    total = items.length;
  }

  return Paged<T>(
    items: items,
    total: total,
    page: resolvedPage,
    limit: resolvedLimit,
  );
}
