/// In-memory holder for the current access/refresh tokens and active tenant.
///
/// Dio interceptors read from this holder synchronously when building each
/// request, and the auth repository writes to it after a successful login or
/// refresh. This avoids re-reading secure storage on every network call while
/// keeping a single source of truth across the app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mutable, reactive token state shared between the auth layer and the network
/// interceptors.
class AuthTokenState {
  const AuthTokenState({
    this.accessToken = '',
    this.refreshToken = '',
    this.activeTenantId = '',
  });

  final String accessToken;
  final String refreshToken;
  final String activeTenantId;

  bool get isAuthenticated => accessToken.isNotEmpty;
  bool get hasTenant => activeTenantId.isNotEmpty;

  AuthTokenState copyWith({
    String? accessToken,
    String? refreshToken,
    String? activeTenantId,
  }) {
    return AuthTokenState(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      activeTenantId: activeTenantId ?? this.activeTenantId,
    );
  }
}

/// Riverpod notifier backing [authTokenProvider].
class AuthTokenNotifier extends Notifier<AuthTokenState> {
  @override
  AuthTokenState build() => const AuthTokenState();

  /// Replaces both tokens (after login or refresh).
  void setTokens({required String access, required String refresh}) {
    state = state.copyWith(accessToken: access, refreshToken: refresh);
  }

  /// Updates only the access token (used after a silent refresh).
  void setAccessToken(String access) =>
      state = state.copyWith(accessToken: access);

  /// Sets the active tenant id used as the `X-Tenant-ID` header.
  void setActiveTenant(String tenantId) =>
      state = state.copyWith(activeTenantId: tenantId);

  /// Clears all tokens (sign out).
  void clear() => state = const AuthTokenState();
}

/// The single source of truth for the current session's tokens + tenant.
final authTokenProvider = NotifierProvider<AuthTokenNotifier, AuthTokenState>(
  AuthTokenNotifier.new,
);
