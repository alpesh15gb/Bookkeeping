/// Persistent, secure storage for authentication credentials and the active
/// tenant. Tokens are stored using platform keychain/keystore via
/// [FlutterSecureStorage]; preferences that are not security-sensitive use
/// [SharedPreferences].
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Last server-validated identity and membership snapshot.
///
/// This contains no password or token. It is stored in the platform keychain
/// alongside the tokens and is used only during a bounded offline launch.
class CachedAuthContext {
  const CachedAuthContext({
    required this.user,
    required this.memberships,
    required this.validatedAt,
  });

  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> memberships;
  final DateTime validatedAt;

  Map<String, dynamic> toJson() => {
    'user': user,
    'memberships': memberships,
    'validated_at': validatedAt.toUtc().toIso8601String(),
  };

  factory CachedAuthContext.fromJson(Map<String, dynamic> json) {
    final rawMemberships = json['memberships'];
    return CachedAuthContext(
      user: (json['user'] as Map).cast<String, dynamic>(),
      memberships: rawMemberships is List
          ? rawMemberships
                .whereType<Map<Object?, Object?>>()
                .map((item) => item.cast<String, dynamic>())
                .toList(growable: false)
          : const [],
      validatedAt: DateTime.parse(json['validated_at'] as String).toUtc(),
    );
  }
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
  static const _kCachedAuthContext = 'cached_auth_context_v1';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  String _fallbackKey(String key) => 'secure_fallback_$key';

  Future<String?> _readSecure(String key) async {
    if (kIsWeb) return _prefs.getString(_fallbackKey(key));
    try {
      return await _secure.read(key: key).timeout(const Duration(seconds: 3));
    } catch (error) {
      developer.log(
        'Secure session read unavailable.',
        name: 'apexbooks.session_storage',
        error: error.runtimeType,
      );
      rethrow;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    if (kIsWeb) {
      await _prefs.setString(_fallbackKey(key), value);
      return;
    }
    try {
      await _secure
          .write(key: key, value: value)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      developer.log(
        'Secure session write unavailable.',
        name: 'apexbooks.session_storage',
        error: error.runtimeType,
      );
      rethrow;
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (kIsWeb) {
      await _prefs.remove(_fallbackKey(key));
      return;
    }
    try {
      await _secure.delete(key: key).timeout(const Duration(seconds: 3));
    } catch (error) {
      developer.log(
        'Secure session delete unavailable; clearing platform fallback.',
        name: 'apexbooks.session_storage',
        error: error.runtimeType,
      );
    }
    await _prefs.remove(_fallbackKey(key));
  }

  /// Reads the full persisted session, or `null` if not signed in.
  Future<StoredSession?> read() async {
    final access = await _readSecure(_kAccessToken);
    final refresh = await _readSecure(_kRefreshToken);
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
    await _writeSecure(_kAccessToken, accessToken);
    await _writeSecure(_kRefreshToken, refreshToken);
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

  Future<CachedAuthContext?> readCachedAuthContext() async {
    final encoded = await _readSecure(_kCachedAuthContext);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return CachedAuthContext.fromJson(decoded.cast<String, dynamic>());
    } catch (error) {
      developer.log(
        'Cached authentication context is invalid.',
        name: 'apexbooks.session_storage',
        error: error.runtimeType,
      );
      return null;
    }
  }

  Future<void> writeCachedAuthContext(CachedAuthContext context) {
    return _writeSecure(_kCachedAuthContext, jsonEncode(context.toJson()));
  }

  /// Updates only the access token (used after a successful refresh).
  Future<void> writeAccessToken(String accessToken) =>
      _writeSecure(_kAccessToken, accessToken);

  /// Clears every persisted credential (sign out).
  Future<void> clear() async {
    await _deleteSecure(_kAccessToken);
    await _deleteSecure(_kRefreshToken);
    await _prefs.remove(_kActiveTenant);
    await _prefs.remove(_kActiveRole);
    await _prefs.remove(_kUserId);
    await _deleteSecure(_kCachedAuthContext);
  }
}

/// Provider for [SessionStorage].
final sessionStorageProvider = Provider<SessionStorage>((ref) {
  final secure = ref.watch(secureStorageProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionStorage(secure, prefs);
});
