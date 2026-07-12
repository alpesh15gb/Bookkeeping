/// Centralized Dio [ApiClient] assembled with all ApexBooks interceptors.
///
/// Repositories obtain a configured [Dio] via [apiClientProvider] and never
/// construct their own HTTP client. This guarantees consistent auth, tenant,
/// idempotency and refresh behavior across every backend call.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../config/env_config.dart';
import 'auth_token_state.dart';
import 'interceptors.dart';
import 'refresh_interceptor.dart';

/// Callback used by [ApiClient] to sign the user out when the refresh token
/// is no longer valid. Overridden in `main.dart` with the auth controller.
typedef SessionExpiredHandler = Future<void> Function(Ref ref);

/// Builds and provides the single app-wide [Dio] instance.
///
/// The [sessionExpiredHandler] is injected from the app bootstrap so this
/// file stays free of feature-layer dependencies.
class ApiClient {
  ApiClient._(this.dio);
  final Dio dio;

  static ApiClient build(
    Ref ref, {
    required SessionExpiredHandler sessionExpiredHandler,
  }) {
    final base = EnvConfig.instance.apiBaseUrl;
    const uuid = Uuid();

    final dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );

    // Wire the token sink so the refresh interceptor can publish new tokens.
    RefreshInterceptor.registerTokenSink((access, refresh) {
      ref
          .read(authTokenProvider.notifier)
          .setTokens(access: access, refresh: refresh);
    });

    dio.interceptors.addAll([
      AuthInterceptor(tokenReaderFrom(ref)),
      TenantInterceptor(tokenReaderFrom(ref)),
      IdempotencyInterceptor(uuid),
      buildRefreshInterceptor(
        ref,
        onSessionExpired: () => sessionExpiredHandler(ref),
      ),
    ]);

    return ApiClient._(dio);
  }
}

/// Provider for the app-wide [Dio] instance. Overridden in `main.dart` with
/// the real session-expired handler once the auth controller is available.
final apiClientProvider = Provider<Dio>((ref) {
  throw UnimplementedError(
    'apiClientProvider must be overridden in main() with ApiClient.build().',
  );
});
