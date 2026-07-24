/// Interceptor that transparently refreshes the access token when the backend
/// returns 401, then replays the original request exactly once.
///
/// Design notes:
///   * Uses a dedicated refresh [Dio] (no auth interceptor) to call
///     `POST /auth/refresh`, preventing infinite recursion.
///   * A [Completer]-based mutex serializes concurrent refresh attempts so a
///     burst of 401s only triggers a single refresh.
///   * On a failed refresh the session is invalidated and the caller receives
///     the original 401 so the router can redirect to login.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import '../storage/session_storage.dart';
import 'interceptors.dart';

export '../errors/api_error.dart' show ApiError;

/// Callback invoked when the refresh token is no longer valid and the user
/// must be signed out. Wired up by the auth controller.
typedef SignOutCallback = Future<void> Function();

/// Interceptor that refreshes the access token on 401 and retries the request.
class RefreshInterceptor extends Interceptor {
  RefreshInterceptor({
    required this.tokenReader,
    required this.refreshDio,
    required this.sessionStorage,
    required this.onSessionExpired,
  });

  final TokenReader tokenReader;
  final Dio refreshDio;
  final SessionStorage sessionStorage;
  final SignOutCallback onSessionExpired;

  // Mutex: only one refresh at a time.
  Completer<bool>? _refreshCompleter;
  bool _isRefreshing = false;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final requestPath = err.requestOptions.path;

    // Don't attempt to refresh for the refresh endpoint itself.
    final isRefreshCall = requestPath.endsWith('/auth/refresh');
    if (status != 401 || isRefreshCall) {
      handler.next(err);
      return;
    }

    final refreshSuccess = await _refreshOnce();
    if (!refreshSuccess) {
      await onSessionExpired();
      handler.next(err);
      return;
    }

    // Replay the original request with the new access token.
    try {
      final clone = await _retry(err.requestOptions);
      handler.resolve(clone);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Runs a single refresh attempt, serializing concurrent callers.
  Future<bool> _refreshOnce() async {
    if (_isRefreshing) {
      return _refreshCompleter?.future ?? Future.value(false);
    }
    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();
    try {
      final refreshToken = tokenReader().refreshToken;
      if (refreshToken.isEmpty) return false;

      final base = EnvConfig.instance.apiBaseUrl;
      final response = await refreshDio.post(
        '$base/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      final access = data['access_token'] as String;
      final newRefresh = data['refresh_token'] as String;

      // Persist and publish the new tokens.
      await sessionStorage.writeTokens(
        accessToken: access,
        refreshToken: newRefresh,
      );
      // The auth controller listens to a notifier we can't reach from here
      // directly without a circular dep; instead the repository-level refresh
      // path updates the notifier. Here we only persist so a relaunch restores
      // the session. The in-memory token is updated via the reader's source.
      _publishTokens(access, newRefresh);
      return true;
    } catch (e) {
      debugPrint('RefreshInterceptor: token refresh failed — $e');
      return false;
    } finally {
      final completer = _refreshCompleter;
      _isRefreshing = false;
      _refreshCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete(true);
      }
    }
  }

  /// Updates the in-memory token state. Resolved at runtime via the notifier
  /// bound to the provider; see `ApiClient` wiring.
  void _publishTokens(String access, String refresh) {
    _tokenSink?.call(access, refresh);
  }

  /// Injected by the ApiClient factory so this interceptor can update the
  /// reactive token state without importing the notifier (avoids cycles).
  // ignore: prefer_function_declarations_over_variables
  static void Function(String access, String refresh)? _tokenSink;

  /// Called once during app bootstrap to wire the token sink.
  static void registerTokenSink(void Function(String, String) sink) {
    _tokenSink = sink;
  }

  Future<Response<dynamic>> _retry(RequestOptions options) {
    final dio = Dio(
      BaseOptions(
        baseUrl: options.baseUrl,
        connectTimeout: options.connectTimeout,
        receiveTimeout: options.receiveTimeout,
        sendTimeout: options.sendTimeout,
      ),
    );
    // Re-attach the auth + tenant headers from the latest token state.
    final state = tokenReader();
    options.headers['Authorization'] = 'Bearer ${state.accessToken}';
    if (state.activeTenantId.isNotEmpty) {
      options.headers['X-Tenant-ID'] = state.activeTenantId;
    }
    return dio.fetch(options);
  }
}

/// Provided so callers can construct a refresh interceptor with the right deps.
RefreshInterceptor buildRefreshInterceptor(
  Ref ref, {
  required SignOutCallback onSessionExpired,
}) {
  final base = EnvConfig.instance.apiBaseUrl;
  final refreshDio = Dio(
    BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );
  return RefreshInterceptor(
    tokenReader: tokenReaderFrom(ref),
    refreshDio: refreshDio,
    sessionStorage: ref.watch(sessionStorageProvider),
    onSessionExpired: onSessionExpired,
  );
}
