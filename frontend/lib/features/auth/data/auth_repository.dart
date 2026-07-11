/// Repository for the ApexBooks authentication & tenant APIs.
///
/// Every method maps directly to a documented endpoint and returns a typed
/// [Result] so callers can render loading/error/success states uniformly.
/// No mock data, no `Future.delayed` — all calls hit the live backend.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_extensions.dart';
import '../../../core/result/result.dart';
import 'models/auth_models.dart';
import 'models/auth_requests.dart';
import 'models/membership_models.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  /// `POST /auth/register` — creates a user and their first tenant.
  Future<Result<UserModel>> register(RegisterRequest req) {
    return guardDio(() async {
      final res = await _dio.post('/auth/register', data: req.toJson());
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `POST /auth/login` — returns access + refresh tokens.
  Future<Result<TokenPair>> login(LoginRequest req) {
    return guardDio(() async {
      final res = await _dio.post('/auth/login', data: req.toJson());
      return TokenPair.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `POST /auth/refresh` — exchanges a refresh token for a new pair.
  Future<Result<TokenPair>> refresh(String refreshToken) {
    return guardDio(() async {
      final res = await _dio.post(
        '/auth/refresh',
        data: RefreshRequest(refreshToken).toJson(),
      );
      return TokenPair.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `POST /auth/logout` — revokes the refresh token.
  Future<Result<void>> logout(String refreshToken) {
    return guardDio(() async {
      await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
    });
  }

  /// `GET /auth/me` — current user profile.
  Future<Result<UserModel>> me() {
    return guardDio(() async {
      final res = await _dio.get('/auth/me');
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `GET /auth/memberships` — all tenants the user belongs to.
  Future<Result<List<Membership>>> memberships() {
    return guardDio(() async {
      final res = await _dio.get('/auth/memberships');
      final data = res.data;
      final list = <Membership>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) list.add(Membership.fromJson(item));
        }
      } else if (data is Map<String, dynamic> && data['items'] is List) {
        for (final item in data['items'] as List) {
          if (item is Map<String, dynamic>) list.add(Membership.fromJson(item));
        }
      }
      return list;
    });
  }

  /// `POST /auth/change-password`.
  Future<Result<void>> changePassword(ChangePasswordRequest req) {
    return guardDio(() async {
      await _dio.post('/auth/change-password', data: req.toJson());
    });
  }

  /// `POST /auth/forgot-password` — sends a reset email.
  Future<Result<void>> forgotPassword(String email) {
    return guardDio(() async {
      await _dio.post(
        '/auth/forgot-password',
        data: ForgotPasswordRequest(email).toJson(),
      );
    });
  }

  /// `POST /auth/reset-password` — resets password with a token.
  Future<Result<void>> resetPassword(ResetPasswordRequest req) {
    return guardDio(() async {
      await _dio.post('/auth/reset-password', data: req.toJson());
    });
  }

  /// `POST /auth/verify-email`.
  Future<Result<void>> verifyEmail(String token) {
    return guardDio(() async {
      await _dio.post('/auth/verify-email', data: {'token': token});
    });
  }

  /// `POST /auth/2fa/enable` — generates a TOTP secret + QR URI.
  Future<Result<TotpSetup>> enable2fa() {
    return guardDio(() async {
      final res = await _dio.post('/auth/2fa/enable');
      return TotpSetup.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// `POST /auth/2fa/verify` — confirms a TOTP code and activates 2FA.
  Future<Result<void>> verify2fa(String token) {
    return guardDio(() async {
      await _dio.post(
        '/auth/2fa/verify',
        data: TotpVerifyRequest(token).toJson(),
      );
    });
  }

  /// `POST /auth/2fa/disable`.
  Future<Result<void>> disable2fa(String token) {
    return guardDio(() async {
      await _dio.post(
        '/auth/2fa/disable',
        data: TotpVerifyRequest(token).toJson(),
      );
    });
  }

  /// `GET /companies/{id}` — full tenant profile.
  Future<Result<Company>> getCompany(String id) {
    return guardDio(() async {
      final res = await _dio.get('/companies/$id');
      return Company.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

/// Provider for [AuthRepository].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});
