/// Persistent, secure storage for authentication credentials and the active
/// tenant. Tokens are stored using platform keychain/keystore via
/// [FlutterSecureStorage]; preferences that are not security-sensitive use
/// [SharedPreferences].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot of the persisted session used to restore the app on launch.
class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.activeTenantId,
    required this.activeRole,
    required this.userId,
  });

  final String accessToken;
  final String refreshToken;
  final String activeTenantId;
  final String activeRole;
  final String userId;

  bool get isValid =>
      accessToken.isNotEmpty &&
      refreshToken.isNotEmpty &&
      activeTenantId.isNotEmpty;
}

/// Provider for the underlying secure storage instance.
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
});

/// Provider for [SharedPreferences] (async-initialized on app startup).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() '
    'with the initialized instance.',
  );
});

/// Centralized token + tenant persistence.
class SessionStorage {
  SessionStorage(this._secure, this._prefs);

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kActiveTenant = 'active_tenant_id';
  static const _kActiveRole = 'active_role';
  static const _kUserId = 'user_id';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  /// Reads the full persisted session, or `null` if not signed in.
  Future<StoredSession?> read() async {
    final access = await _secure.read(key: _kAccessToken);
    final refresh = await _secure.read(key: _kRefreshToken);
    final tenant = _prefs.getString(_kActiveTenant);
    final role = _prefs.getString(_kActiveRole);
    final userId = _prefs.getString(_kUserId);
    if (access == null ||
        refresh == null ||
        tenant == null ||
        role == null ||
        userId == null) {
      return null;
    }
    return StoredSession(
      accessToken: access,
      refreshToken: refresh,
      activeTenantId: tenant,
      activeRole: role,
      userId: userId,
    );
  }

  /// Persists the active access/refresh tokens.
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secure.write(key: _kAccessToken, value: accessToken);
    await _secure.write(key: _kRefreshToken, value: refreshToken);
  }

  /// Persists the active tenant, role and user id.
  Future<void> writeActiveContext({
    required String tenantId,
    required String role,
    required String userId,
  }) async {
    await _prefs.setString(_kActiveTenant, tenantId);
    await _prefs.setString(_kActiveRole, role);
    await _prefs.setString(_kUserId, userId);
  }

  /// Updates only the access token (used after a successful refresh).
  Future<void> writeAccessToken(String accessToken) =>
      _secure.write(key: _kAccessToken, value: accessToken);

  /// Clears every persisted credential (sign out).
  Future<void> clear() async {
    await _secure.delete(key: _kAccessToken);
    await _secure.delete(key: _kRefreshToken);
    await _prefs.remove(_kActiveTenant);
    await _prefs.remove(_kActiveRole);
    await _prefs.remove(_kUserId);
  }
}

/// Provider for [SessionStorage].
final sessionStorageProvider = Provider<SessionStorage>((ref) {
  final secure = ref.watch(secureStorageProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionStorage(secure, prefs);
});
