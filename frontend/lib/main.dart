/// ApexBooks app entry point.
///
/// Bootstrap sequence:
///   1. Load `.env` from assets and initialize [EnvConfig].
///   2. Initialize [SharedPreferences] (required by session + theme storage).
///   3. Build the [ProviderScope] overrides for [sharedPreferencesProvider]
///      and [apiClientProvider] (the latter wires the refresh-on-401 handler
///      to the auth controller).
///   4. After the first frame, restore the persisted session.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/apex_app.dart';
import 'core/config/env_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_storage.dart';
import 'features/auth/presentation/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load environment config — falls back to defaults if .env is missing.
  try {
    final envContent = await rootBundle.loadString('.env');
    EnvConfig.initialize(envContent);
  } catch (_) {
    // .env not bundled — use production defaults from EnvConfig.
    EnvConfig.initialize('');
  }

  // 2. Initialize shared preferences used by session + theme storage.
  final prefs = await SharedPreferences.getInstance();

  // 3. Build the container with the required overrides. The API client is
  //    constructed with a session-expired handler that delegates to the auth
  //    controller, so a dead refresh token transparently signs the user out.
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWith((ref) {
        return ApiClient.build(
          ref,
          sessionExpiredHandler: (ref) async {
            await ref
                .read(authControllerProvider.notifier)
                .handleSessionExpired();
          },
        ).dio;
      }),
    ],
  );

  // 4. Restore the session (sets auth status → authenticated or unauthenticated,
  //    which the router's redirect reacts to).
  await container.read(authControllerProvider.notifier).restore();

  runApp(
    UncontrolledProviderScope(container: container, child: const ApexApp()),
  );
}
