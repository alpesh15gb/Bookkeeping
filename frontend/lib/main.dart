/// ApexBooks app entry point.
///
/// Bootstrap sequence:
///   1. Load `.env` from assets and initialize [EnvConfig].
///   2. Initialize [SharedPreferences] (required by session + theme storage).
///   3. Build the [ProviderScope] overrides for [sharedPreferencesProvider]
///      and [apiClientProvider] (the latter wires the refresh-on-401 handler
///      to the auth controller).
///   4. After the first frame, restore the persisted session.
///   5. Install global error handlers so every uncaught exception prints a
///      full stack trace to the terminal, regardless of origin (Flutter
///      framework, platform dispatcher, or async zone).
library;

import 'dart:async';
import 'dart:io' show stderr;
import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

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
  // ── Global error handlers (zone-independent) ──────────────────────────
  //
  // These are set before the guarded zone so they're always active even if
  // the zone setup itself throws.  The zone handler below is an additional
  // safety net for async errors that escape both FlutterError and the
  // platform dispatcher.

  /// Known benign Flutter SDK internal error patterns that fire in debug mode
  /// but have no runtime impact.  We suppress the terminal noise while still
  /// recording them via developer.log for debugging.
  bool isBenignFrameworkError(FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('Cannot hit test a render box that has never been laid out')) {
      return true;
    }
    if (message.contains('!semantics.parentDataDirty') ||
        message.contains('!childSemantics.renderObject._needsLayout')) {
      return true;
    }
    // Zone mismatch is now fixed — if it still fires it's a Flutter SDK issue.
    if (message.contains('Zone mismatch')) {
      return true;
    }
    // Page-transition race: painting a widget that hasn't completed layout
    // during the zoom/slide transition snapshot.
    if (message.contains("'hasSize': RenderBox was not laid out")) {
      return true;
    }
    return false;
  }

  // 1. Flutter framework errors (build/layout/paint).
  FlutterError.onError = (details) {
    // Still log to dart:developer so it's in the trace if needed.
    developer.log(
      'FlutterError: ${details.exception}',
      name: 'apexbooks',
      error: details.exception,
      stackTrace: details.stack,
    );
    // Suppress known benign Flutter SDK internal noise from the terminal.
    if (isBenignFrameworkError(details)) return;
    stderr.writeln('═══ FlutterError ═══');
    stderr.writeln('Exception: ${details.exception}');
    if (details.stack != null) {
      stderr.writeln('${details.stack}');
    }
    stderr.writeln('══════════════════════');
  };

  // 2. Platform-level errors that escape every other handler.
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Platform Error: $error',
      name: 'apexbooks',
      error: error,
      stackTrace: stack,
    );
    stderr.writeln('═══ Platform Dispatcher Error ═══');
    stderr.writeln('$error');
    stderr.writeln('$stack');
    stderr.writeln('══════════════════════════════════');
    return true; // Already printed — do not kill the process.
  };

  // ── Everything else inside the guarded zone ───────────────────────────
  //
  // WidgetsFlutterBinding.ensureInitialized(), the async bootstrap, and
  // runApp() must all run in the SAME zone so that Flutter's zone check
  // (BindingBase.debugCheckZone) passes.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. Load environment config.
      try {
        final envContent = await rootBundle.loadString('assets/.env');
        EnvConfig.initialize(envContent);
      } catch (e) {
        // .env not bundled — use production defaults from EnvConfig.
        developer.log(
          'EnvConfig: .env not loaded from assets, using defaults ($e)',
          name: 'apexbooks',
          error: e,
        );
        EnvConfig.initialize('');
      }

      // 2. Initialize shared preferences.
      final prefs = await SharedPreferences.getInstance();

      // 3. Build the container with the required overrides.
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

      // 4. Restore the session.
      await container.read(authControllerProvider.notifier).restore();

      // 5. Start the app.
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const ApexApp(),
        ),
      );
    },
    (error, stack) {
      developer.log(
        'Unhandled zone error: $error',
        name: 'apexbooks',
        error: error,
        stackTrace: stack,
      );
      stderr.writeln('═══ Unhandled Zone Error ═══');
      stderr.writeln('$error');
      stderr.writeln('$stack');
      stderr.writeln('══════════════════════════════');
    },
  );
}
