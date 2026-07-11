/// In-memory cache + request deduplication service.
///
/// Provides two capabilities used across all repositories:
///   * **TTL cache** — list/detail responses are cached with an expiry so
///     rapid back-navigation doesn't re-hit the network.
///   * **Request dedup** — concurrent identical in-flight requests share a
///     single future, preventing thundering-herd duplicate API calls.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../logging/logger_service.dart';

/// A cached entry with an expiry timestamp.
class _CacheEntry<T> {
  _CacheEntry(this.value, this.expiresAt);
  final T value;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Centralized cache + dedup. Generic over the value type so it can store
/// `Paged<Contact>`, `Contact`, `List<Account>`, etc.
class CacheService {
  CacheService(this._logger);

  final LoggerService _logger;
  final _cache = <String, _CacheEntry<Object?>>{};
  final _inflight = <String, Future<Object?>>{};

  /// Reads a cached value for [key] if present and not expired, else `null`.
  T? read<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  /// Writes [value] under [key] with [ttl].
  void write<T>(String key, T value, {Duration? ttl}) {
    final expiry = DateTime.now().add(ttl ?? AppConstants.listCacheTtl);
    _cache[key] = _CacheEntry<Object?>(value, expiry);
  }

  /// Removes a cached entry (call after a mutation invalidates it).
  void invalidate(String key) {
    _cache.remove(key);
    _inflight.remove(key);
  }

  /// Removes all cache entries matching a prefix (e.g. invalidate all
  /// `contacts:*` entries after creating/deleting a contact).
  void invalidatePrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
    _inflight.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Clears the entire cache (on sign-out / tenant switch).
  void clear() {
    _cache.clear();
    _inflight.clear();
    _logger.debug('CacheService cleared');
  }

  /// Deduplicates concurrent calls to [loader] for the same [key]. If a
  /// request with [key] is already in flight, its future is shared.
  Future<T> dedup<T>(String key, Future<T> Function() loader) async {
    final existing = _inflight[key];
    if (existing != null) {
      return existing.then((v) => v as T);
    }
    final completer = loader().then<Object?>((v) => v).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = completer;
    return completer.then((v) => v as T);
  }

  /// Combines cache + dedup: returns the cached value if fresh, otherwise
  /// deduplicates a fresh [loader] call and caches the result.
  Future<T> cached<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) async {
    final cachedValue = read<T>(key);
    if (cachedValue != null) return cachedValue;
    final value = await dedup(key, loader);
    write(key, value, ttl: ttl);
    return value;
  }
}

/// Provider for [CacheService].
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService(ref.watch(loggerProvider));
});
