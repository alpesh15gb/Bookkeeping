/// Dio interceptors that implement the ApexBooks auth, tenant and idempotency
/// contract documented in `AUTHENTICATION_GUIDE.md`.
///
///   * [AuthInterceptor] attaches `Authorization: Bearer <access_token>`.
///   * [TenantInterceptor] attaches `X-Tenant-ID: <tenant-uuid>` for every
///     request that requires it (skips the public auth endpoints).
///   * [IdempotencyInterceptor] adds a unique `Idempotency-Key` header to all
///     POST/PUT requests that create or modify data, preventing accidental
///     duplicate submissions on network retry.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'auth_token_state.dart';

/// A small abstraction so interceptors can read the token state without a
/// hard dependency on Riverpod's container lifecycle inside Dio.
typedef TokenReader = AuthTokenState Function();

/// Builds a [TokenReader] bound to [provider].
TokenReader tokenReaderFrom(Ref ref) =>
    () => ref.read(authTokenProvider);

/// Endpoints that must NOT receive the `X-Tenant-ID` header (public auth).
const _noTenantPaths = <String>{
  '/auth/login',
  '/auth/register',
  '/auth/refresh',
  '/auth/forgot-password',
  '/auth/reset-password',
  '/auth/verify-email',
  '/health',
};

/// Attaches the bearer access token to every authenticated request.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._read);
  final TokenReader _read;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _read().accessToken;
    if (token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Attaches `X-Tenant-ID` to every request except the public auth endpoints.
class TenantInterceptor extends Interceptor {
  TenantInterceptor(this._read);
  final TokenReader _read;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    // path may be absolute (with host) or relative; compare the tail.
    final isPublic = _noTenantPaths.any((p) => path.endsWith(p));
    if (!isPublic) {
      final tenant = _read().activeTenantId;
      if (tenant.isNotEmpty) {
        options.headers['X-Tenant-ID'] = tenant;
      }
    }
    handler.next(options);
  }
}

/// Adds an `Idempotency-Key` to all POST/PUT data-modifying requests that do
/// not already specify one. This lets the backend safely deduplicate retries.
class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor(this._uuid);
  final Uuid _uuid;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    if ((method == 'POST' || method == 'PUT') &&
        !options.headers.containsKey('Idempotency-Key')) {
      options.headers['Idempotency-Key'] = _uuid.v4();
    }
    handler.next(options);
  }
}
