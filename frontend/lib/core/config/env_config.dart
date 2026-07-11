/// Environment configuration loaded from `.env` at app startup.
///
/// Values are read from the Flutter asset `.env` bundled with the app and can
/// be overridden for local development. The production deployment targets the
/// live ApexBooks backend described in the backend documentation.
class EnvConfig {
  EnvConfig._({
    required this.apiBaseUrl,
    required this.staticBaseUrl,
    required this.appName,
  });

  /// The configured environment for the current build.
  static EnvConfig? _instance;

  /// Base URL for all REST API calls, e.g. `https://api.apexbooks.in/api/v1`.
  final String apiBaseUrl;

  /// Base URL for static assets (logos, etc.), e.g. `https://api.apexbooks.in/static`.
  final String staticBaseUrl;

  /// Human-readable application name shown in the UI.
  final String appName;

  /// Returns the active [EnvConfig], throwing if it has not been initialized.
  static EnvConfig get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        'EnvConfig has not been initialized. Call EnvConfig.initialize first.',
      );
    }
    return current;
  }

  /// Whether [initialize] has been called with a valid configuration.
  static bool get isInitialized => _instance != null;

  /// Initializes the configuration from the raw `.env` content.
  ///
  /// Each line is expected to follow `KEY=VALUE`. Lines starting with `#` and
  /// blank lines are ignored. Missing keys fall back to sensible production
  /// defaults so the app is always able to talk to a backend.
  static void initialize(String envContent) {
    final map = _parse(envContent);
    _instance = EnvConfig._(
      apiBaseUrl: (map['API_BASE_URL']?.trim().isNotEmpty ?? false)
          ? map['API_BASE_URL']!.trim()
          : 'https://api.apexbooks.in/api/v1',
      staticBaseUrl: (map['STATIC_BASE_URL']?.trim().isNotEmpty ?? false)
          ? map['STATIC_BASE_URL']!.trim()
          : 'https://api.apexbooks.in/static',
      appName: (map['APP_NAME']?.trim().isNotEmpty ?? false)
          ? map['APP_NAME']!.trim()
          : 'ApexBooks',
    );
  }

  static Map<String, String> _parse(String content) {
    final result = <String, String>{};
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex == -1) continue;
      final key = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }
}
