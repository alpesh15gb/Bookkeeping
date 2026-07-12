/// API version layer. All backend URLs are built here so that a version bump
/// only touches one file.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';

/// Supported API versions.
enum ApiVersion { v1, v2 }

/// Base URL builder.
class ApiUrl {
  ApiUrl._();

  static ApiVersion _version = ApiVersion.v1;

  /// Override the active version at boot (e.g. from remote config).
  static void setVersion(ApiVersion v) => _version = v;

  /// The version path segment, e.g. `v1`.
  static String get versionPath => switch (_version) {
    ApiVersion.v1 => 'v1',
    ApiVersion.v2 => 'v2',
  };

  /// Full API base, e.g. `https://api.apexbooks.in/api/v1`.
  static String get base => '${EnvConfig.instance.apiBaseUrl}/api/$versionPath';

  /// Convenience: returns the full URL for a relative path (e.g. `/auth/login`).
  static String url(String relativePath) {
    final clean = relativePath.startsWith('/')
        ? relativePath
        : '/$relativePath';
    return '$base$clean';
  }

  /// Convenience for building query-parameter URLs.
  static Uri uri(String relativePath, [Map<String, dynamic>? params]) {
    final u = Uri.parse(url(relativePath));
    if (params != null && params.isNotEmpty) {
      return u.replace(
        queryParameters: params.map((k, v) => MapEntry(k, '$v')),
      );
    }
    return u;
  }
}

/// Provider exposing the current base URL (for use with Dio's `baseUrl`).
final apiBaseUrlProvider = Provider<String>((_) => ApiUrl.base);
