/// Generic CRUD repository base. Concrete repositories (Contacts, Products,
/// Accounts, ...) extend this and supply only:
///   * the Dio instance,
/// * the resource path (e.g. `/masters/contacts`),
/// * a factory that parses one record, and
/// * optional cache configuration.
///
/// All list/get/create/update/delete calls return typed [Result]s, use the
/// [CacheService] for reads and invalidate on writes, and never use mock data.
library;

import 'package:dio/dio.dart';

import '../cache/cache_service.dart';
import '../network/dio_extensions.dart';
import '../result/result.dart';
import 'base_model.dart';

/// A paged list result.
typedef PagedResult<T> = Paged<T>;

/// Generic repository implementing the common ApexBooks CRUD contract.
abstract class BaseRepository<T extends BaseModel> {
  BaseRepository(this._dio, this._cache);

  final Dio _dio;
  final CacheService _cache;

  /// The resource base path, e.g. `/masters/contacts`.
  String get path;

  /// Parses one record from JSON.
  T parseOne(Map<String, dynamic> json);

  /// Cache prefix used to namespace this repository's entries, e.g. `contacts`.
  String get cachePrefix;

  /// `GET {path}` — paginated list honoring [ListQuery].
  Future<Result<Paged<T>>> list(ListQuery query) {
    return guardDio(() async {
      final key = query.cacheKey(cachePrefix);
      return _cache.cached(key, () async {
        final res = await _dio.get(
          path,
          queryParameters: query.toQueryParams(),
        );
        // The ApexBooks masters endpoints return a flat JSON array
        // (`List[...]`) rather than an `{items,total,page,limit}` envelope.
        // [parsePaged] tolerates both shapes.
        return parsePaged<T>(
          res.data,
          parseOne,
          page: query.page,
          limit: query.limit,
        );
      }, ttl: AppConstants.listCacheTtl);
    });
  }

  /// `GET {path}/{id}` — single record.
  Future<Result<T>> get(String id) {
    return guardDio(() async {
      return _cache.cached('$cachePrefix:detail:$id', () async {
        final res = await _dio.get('$path/$id');
        return parseOne(res.data as Map<String, dynamic>);
      }, ttl: AppConstants.detailCacheTtl);
    });
  }

  /// `POST {path}` — create. Invalidates the list cache for this resource.
  Future<Result<T>> create(Map<String, dynamic> body) {
    return guardDio(() async {
      final res = await _dio.post(path, data: body);
      _cache.invalidatePrefix('$cachePrefix:');
      return parseOne(res.data as Map<String, dynamic>);
    });
  }

  /// `PUT {path}/{id}` — update. Invalidates detail + list cache.
  Future<Result<T>> update(String id, Map<String, dynamic> body) {
    return guardDio(() async {
      final res = await _dio.put('$path/$id', data: body);
      _cache.invalidate('$cachePrefix:detail:$id');
      _cache.invalidatePrefix('$cachePrefix:');
      return parseOne(res.data as Map<String, dynamic>);
    });
  }

  /// `DELETE {path}/{id}` — soft-delete. Invalidates caches.
  Future<Result<void>> delete(String id) {
    return guardDio(() async {
      await _dio.delete('$path/$id');
      _cache.invalidate('$cachePrefix:detail:$id');
      _cache.invalidatePrefix('$cachePrefix:');
    });
  }

  /// `POST {path}/bulk-delete` — bulk delete by ids (where supported).
  Future<Result<void>> bulkDelete(List<String> ids) {
    return guardDio(() async {
      await _dio.post('$path/bulk-delete', data: {'ids': ids});
      _cache.invalidatePrefix('$cachePrefix:');
    });
  }
}
