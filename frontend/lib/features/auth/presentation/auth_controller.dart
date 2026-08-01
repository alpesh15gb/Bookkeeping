/// Central auth/session controller for the ApexBooks app.
///
/// Responsibilities:
///   * Hold the authenticated [UserModel], the list of [Membership]s and the
///     active membership.
///   * Execute login / register / forgot-password / reset-password and persist
///     tokens + active tenant.
///   * Restore the session from secure storage on app launch.
///   * Switch the active tenant (company) at runtime.
///   * Sign out (clears storage + in-memory state + notifies the router).
library;

import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_token_state.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/session_storage.dart';
import '../data/auth_repository.dart';
import '../data/models/auth_models.dart';
import '../data/models/auth_requests.dart';
import '../data/models/membership_models.dart';

// Re-export so screens importing this controller also get the Result types
// and the ResultX extension (isFailure / isSuccess / errorOrNull / ...).
export '../../../core/result/result.dart';

/// The four lifecycle phases the auth flow can be in.
enum AuthStatus { initial, authenticated, unauthenticated }

/// Immutable snapshot of the auth/session state consumed by the router and UI.
class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.memberships = const [],
    this.activeMembership,
    this.isLoading = false,
    this.isOfflineSession = false,
    this.error,
  });

  final AuthStatus status;
  final UserModel? user;
  final List<Membership> memberships;
  final Membership? activeMembership;
  final bool isLoading;
  final bool isOfflineSession;
  final ApiError? error;

  /// `true` once the user has selected (or has a single) active company.
  bool get hasActiveTenant => activeMembership != null;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    List<Membership>? memberships,
    Membership? activeMembership,
    bool? isLoading,
    bool? isOfflineSession,
    ApiError? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      memberships: memberships ?? this.memberships,
      activeMembership: activeMembership ?? this.activeMembership,
      isLoading: isLoading ?? this.isLoading,
      isOfflineSession: isOfflineSession ?? this.isOfflineSession,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier backing [authControllerProvider].
class AuthController extends Notifier<AuthState> {
  static const offlineAuthorizationWindow = Duration(days: 7);

  late final AuthRepository _repo;
  late final SessionStorage _storage;
  Future<void>? _restoreInFlight;

  @override
  AuthState build() {
    _repo = ref.watch(authRepositoryProvider);
    _storage = ref.watch(sessionStorageProvider);
    return const AuthState();
  }

  /// Restores the session from secure storage on app launch. Sets the status
  /// to `authenticated`/`unauthenticated` and primes the in-memory token state.
  Future<void> restore() {
    final inFlight = _restoreInFlight;
    if (inFlight != null) return inFlight;

    final operation = _restoreInternal();
    _restoreInFlight = operation;
    operation.whenComplete(() {
      if (identical(_restoreInFlight, operation)) _restoreInFlight = null;
    });
    return operation;
  }

  Future<void> _restoreInternal() async {
    try {
      final stored = await _storage.read();
      if (stored == null || !stored.isValid) {
        await _finishUnauthenticated(clearStorage: true);
        return;
      }
      String tenantKey(String value) =>
          value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      final storedTenantId = stored.activeTenantId.trim();
      final storedTenantKey = tenantKey(storedTenantId);

      ref
          .read(authTokenProvider.notifier)
          .setTokens(access: stored.accessToken, refresh: stored.refreshToken);
      ref.read(authTokenProvider.notifier).setActiveTenant(storedTenantId);

      final meResult = await _repo.me();
      final membershipsResult = await _repo.memberships();
      if (meResult is! Success<UserModel> ||
          membershipsResult is! Success<List<Membership>>) {
        final failures = <ApiError>[
          if (meResult is Failure<UserModel>) meResult.error,
          if (membershipsResult is Failure<List<Membership>>)
            membershipsResult.error,
        ];
        final rejected = failures.any(
          (error) => error.isUnauthorized || error.isForbidden,
        );
        final transient =
            failures.isNotEmpty &&
            failures.every((error) => error.isNetwork || error.isServer);
        if (!rejected && transient) {
          final restored = await _restoreCachedContext(
            storedTenantKey: storedTenantKey,
            tenantKey: tenantKey,
          );
          if (restored) return;
        }
        await _finishUnauthenticated(clearStorage: rejected);
        return;
      }

      final memberships = membershipsResult.value
          .where((membership) => membership.tenantId.isNotEmpty)
          .toList(growable: false);
      Membership? active;
      for (final membership in memberships) {
        final matchesStoredTenant =
            tenantKey(membership.tenantId) == storedTenantKey;
        if (matchesStoredTenant && membership.isActive) {
          active = membership;
          break;
        }
      }
      if (active == null) {
        await _finishUnauthenticated(clearStorage: true);
        return;
      }

      await _cacheValidatedContext(meResult.value, memberships);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: meResult.value,
        memberships: memberships,
        activeMembership: active,
        isOfflineSession: false,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Persisted session restore failed; returning to login.',
        name: 'apexbooks.auth.restore',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      await _finishUnauthenticated(clearStorage: true);
    }
  }

  Future<bool> _restoreCachedContext({
    required String storedTenantKey,
    required String Function(String value) tenantKey,
  }) async {
    final cached = await _storage.readCachedAuthContext();
    if (cached == null ||
        DateTime.now().toUtc().difference(cached.validatedAt) >
            offlineAuthorizationWindow) {
      return false;
    }
    try {
      final user = UserModel.fromJson(cached.user);
      final memberships = cached.memberships
          .map(Membership.fromJson)
          .where((membership) => membership.tenantId.isNotEmpty)
          .toList(growable: false);
      final active = memberships
          .where(
            (membership) =>
                membership.isActive &&
                tenantKey(membership.tenantId) == storedTenantKey,
          )
          .firstOrNull;
      if (!user.isActive || active == null) return false;
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        memberships: memberships,
        activeMembership: active,
        isOfflineSession: true,
      );
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Unable to restore cached offline authorization.',
        name: 'apexbooks.auth.restore',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _cacheValidatedContext(
    UserModel user,
    List<Membership> memberships,
  ) {
    return _storage.writeCachedAuthContext(
      CachedAuthContext(
        user: user.toJson(),
        memberships: memberships
            .map((membership) => membership.toJson())
            .toList(growable: false),
        validatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _finishUnauthenticated({bool clearStorage = false}) async {
    if (clearStorage) {
      try {
        await _storage.clear();
      } catch (error, stackTrace) {
        developer.log(
          'Unable to clear invalid persisted session.',
          name: 'apexbooks.auth.restore',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
      }
    }
    ref.read(authTokenProvider.notifier).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Signs in with [email]/[password] and hydrates the session.
  Future<Result<void>> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.login(
      LoginRequest(email: email, password: password),
    );
    return switch (result) {
      Success<TokenPair>(:final value) => await _onAuthenticated(value),
      Failure<TokenPair>(:final error) => () {
        state = state.copyWith(isLoading: false, error: error);
        return Failure<void>(error);
      }(),
      _ => const Failure<void>(ApiError(message: 'Unexpected response.')),
    };
  }

  /// Registers a new user + company, then signs the user in automatically.
  Future<Result<void>> register(RegisterRequest req) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.register(req);
    if (result is Failure<UserModel>) {
      state = state.copyWith(isLoading: false, error: result.error);
      return Failure<void>(result.error);
    }
    // Auto-login after a successful registration.
    final loginResult = await _repo.login(
      LoginRequest(email: req.email, password: req.password),
    );
    return switch (loginResult) {
      Success<TokenPair>(:final value) => await _onAuthenticated(value),
      Failure<TokenPair>(:final error) => () {
        state = state.copyWith(isLoading: false, error: error);
        return Failure<void>(error);
      }(),
      _ => const Failure<void>(ApiError(message: 'Unexpected response.')),
    };
  }

  /// Sends a password-reset email.
  Future<Result<void>> forgotPassword(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.forgotPassword(email);
    state = state.copyWith(isLoading: false);
    return switch (result) {
      Success<void>() => const Success<void>(null),
      Failure<void>(:final error) => () {
        state = state.copyWith(error: error);
        return Failure<void>(error);
      }(),
      _ => const Failure<void>(ApiError(message: 'Unexpected response.')),
    };
  }

  /// Resets the password using a token received by email.
  Future<Result<void>> resetPassword(ResetPasswordRequest req) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.resetPassword(req);
    state = state.copyWith(isLoading: false);
    return switch (result) {
      Success<void>() => const Success<void>(null),
      Failure<void>(:final error) => () {
        state = state.copyWith(error: error);
        return Failure<void>(error);
      }(),
      _ => const Failure<void>(ApiError(message: 'Unexpected response.')),
    };
  }

  /// Re-fetches memberships to pick up changes like tax_mode.
  Future<void> refreshMemberships() async {
    final result = await _repo.memberships();
    if (result is Success<List<Membership>>) {
      final memberships = result.value;
      final current = state.activeMembership;
      Membership? updated;
      if (current != null) {
        updated = memberships
            .where((m) => m.tenantId == current.tenantId)
            .firstOrNull;
      }
      state = state.copyWith(
        memberships: memberships,
        activeMembership: updated ?? memberships.firstOrNull,
        isOfflineSession: false,
      );
      final user = state.user;
      if (user != null) await _cacheValidatedContext(user, memberships);
    }
  }

  /// Selects the active company/tenant. Persists the choice and primes the
  /// token holder's tenant id so subsequent requests carry the header.
  Future<void> selectTenant(Membership membership) async {
    ref.read(authTokenProvider.notifier).setActiveTenant(membership.tenantId);
    await _storage.writeActiveContext(
      tenantId: membership.tenantId,
      role: membership.role.wire,
      userId: state.user?.id ?? '',
    );
    state = state.copyWith(activeMembership: membership);
  }

  /// Signs the user out: revokes the refresh token, clears storage + state.
  Future<void> signOut() async {
    final refresh = ref.read(authTokenProvider).refreshToken;
    if (refresh.isNotEmpty) {
      await _repo.logout(refresh);
    }
    await _storage.clear();
    ref.read(authTokenProvider.notifier).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Called by the refresh interceptor when the refresh token is no longer
  /// valid. Forces a sign-out without attempting another refresh.
  Future<void> handleSessionExpired() async {
    await _storage.clear();
    ref.read(authTokenProvider.notifier).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Common post-authentication flow: persist tokens, fetch profile +
  /// memberships, then pick the active tenant (auto if only one).
  Future<Result<void>> _onAuthenticated(TokenPair tokens) async {
    await _storage.writeTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    ref
        .read(authTokenProvider.notifier)
        .setTokens(access: tokens.accessToken, refresh: tokens.refreshToken);

    final meResult = await _repo.me();
    if (meResult is! Success<UserModel>) {
      final err = (meResult as Failure<UserModel>).error;
      state = state.copyWith(isLoading: false, error: err);
      return Failure<void>(err);
    }

    final membershipsResult = await _repo.memberships();
    if (membershipsResult is! Success<List<Membership>>) {
      final err = (membershipsResult as Failure<List<Membership>>).error;
      state = state.copyWith(isLoading: false, error: err);
      return Failure<void>(err);
    }

    final memberships = membershipsResult.value;
    final active = memberships.isEmpty ? null : memberships.first;
    if (active != null) {
      ref.read(authTokenProvider.notifier).setActiveTenant(active.tenantId);
      await _storage.writeActiveContext(
        tenantId: active.tenantId,
        role: active.role.wire,
        userId: meResult.value.id,
      );
    }

    state = AuthState(
      status: AuthStatus.authenticated,
      user: meResult.value,
      memberships: memberships,
      activeMembership: active,
      isLoading: false,
      isOfflineSession: false,
    );
    await _cacheValidatedContext(meResult.value, memberships);
    return const Success<void>(null);
  }
}

/// The app-wide auth/session controller.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Single source of truth for whether GST features are enabled.
/// Derived from the active membership's tax_mode.
final gstEnabledProvider = Provider<bool>((ref) {
  final membership = ref.watch(authControllerProvider).activeMembership;
  if (membership == null) return false;
  return membership.taxMode != null && membership.taxMode != 'NON_GST';
});

/// Whether outward documents may collect GST from the customer.
/// Composition and non-GST businesses issue bills of supply and must not
/// charge GST, even though composition businesses remain GST-registered.
final gstCollectionEnabledProvider = Provider<bool>((ref) {
  final membership = ref.watch(authControllerProvider).activeMembership;
  return membership?.taxMode == 'GST_REGULAR';
});
