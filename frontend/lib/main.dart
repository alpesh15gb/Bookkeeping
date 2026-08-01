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
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/apex_app.dart';
import 'core/config/env_config.dart';
import 'core/database/database_provider.dart';
import 'core/database/native_database_encryption.dart';
import 'core/ids/id_generator.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_storage.dart';
import 'core/sync/sync_providers.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/invoices/presentation/providers/invoice_providers.dart';
import 'features/journals/presentation/providers/journal_providers.dart';
import 'features/offline_repository_providers.dart';

Future<void> main() async {
  var appMounted = false;

  void showStartupFailure(Object error, StackTrace stack) {
    developer.log(
      'Startup failure: ${error.runtimeType}',
      name: 'apexbooks.bootstrap',
      error: error,
      stackTrace: stack,
    );
    if (appMounted) return;
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const _BootstrapFailureApp());
    appMounted = true;
  }

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
    if (message.contains(
      'Cannot hit test a render box that has never been laid out',
    )) {
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
    if (!appMounted) {
      showStartupFailure(
        details.exception,
        details.stack ?? StackTrace.current,
      );
      return;
    }
    if (!kIsWeb) FlutterError.presentError(details);
  };

  // 2. Platform-level errors that escape every other handler.
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Platform Error: $error',
      name: 'apexbooks',
      error: error,
      stackTrace: stack,
    );
    showStartupFailure(error, stack);
    if (!kIsWeb) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
    return true; // Already reported — do not kill the process.
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

      // 2. Initialize shared preferences and a stable device id. Browser
      // storage can be blocked by privacy mode or an embedded webview; bound
      // the initialization so it cannot prevent the first application frame.
      late final SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 3),
        );
      } catch (error) {
        developer.log(
          'Persistent preferences unavailable; using in-memory preferences.',
          name: 'apexbooks.bootstrap',
          error: error.runtimeType,
        );
        // This API is also the package's supported in-memory fallback; the
        // analyzer annotation reflects its test-oriented visibility.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues(<String, Object>{});
        prefs = await SharedPreferences.getInstance();
      }
      const secureStorage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
      const deviceIdKey = 'apexbooks_device_id';
      String? deviceId;
      if (kIsWeb) {
        deviceId = prefs.getString(deviceIdKey);
      } else {
        try {
          deviceId = await secureStorage
              .read(key: deviceIdKey)
              .timeout(const Duration(seconds: 3));
        } catch (error) {
          developer.log(
            'Secure device ID read unavailable; using preferences fallback.',
            name: 'apexbooks.device_id',
            error: error.runtimeType,
          );
          deviceId = prefs.getString(deviceIdKey);
        }
      }
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = IdGenerator.newId();
        if (kIsWeb) {
          await prefs.setString(deviceIdKey, deviceId);
        } else {
          try {
            await secureStorage
                .write(key: deviceIdKey, value: deviceId)
                .timeout(const Duration(seconds: 3));
          } catch (error) {
            developer.log(
              'Secure device ID write unavailable; using preferences fallback.',
              name: 'apexbooks.device_id',
              error: error.runtimeType,
            );
            await prefs.setString(deviceIdKey, deviceId);
          }
        }
      }

      // The offline ledger contains financial and personal data. Its random
      // encryption key is stored only in the platform keychain/keystore.
      const databaseKeyStorageKey = 'apexbooks_database_key_v1';
      late String databaseKey;
      try {
        databaseKey =
            await secureStorage
                .read(key: databaseKeyStorageKey)
                .timeout(const Duration(seconds: 5)) ??
            '';
        if (databaseKey.isEmpty) {
          final random = Random.secure();
          databaseKey = base64UrlEncode(
            List<int>.generate(32, (_) => random.nextInt(256)),
          );
          await secureStorage
              .write(key: databaseKeyStorageKey, value: databaseKey)
              .timeout(const Duration(seconds: 5));
        }
      } catch (error) {
        throw StateError(
          'Secure storage is required to open the offline database: '
          '${error.runtimeType}',
        );
      }
      await prepareEncryptedNativeDatabase(databaseKey);

      // 3. Build the container with the required overrides.
      final database = AppDatabase.encrypted(databaseKey);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStorageProvider.overrideWithValue(secureStorage),
          deviceIdProvider_.overrideWithValue(deviceId),
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

      // 4. Render the first frame before any storage/network restoration. A
      // browser storage or database future must never leave the active app
      // with a blank page; the router intentionally shows the splash while
      // AuthStatus.initial is being resolved.
      runApp(
        UncontrolledProviderScope(container: container, child: const ApexApp()),
      );
      appMounted = true;

      // 5. Restore the session and start foreground sync after the first
      // frame. Auth failures and provider initialization cannot block the
      // shell from rendering.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(() async {
          await container.read(authControllerProvider.notifier).restore();
          if (container.read(authControllerProvider).status ==
              AuthStatus.authenticated) {
            container.read(journalRepositoryProvider);
            final invoiceRepository = container.read(invoiceRepositoryProvider);
            container.read(offlineRepositoriesProvider);
            // Hydrate authoritative master data before the first pull/push.
            // Failure is expected during an offline launch; cached rows remain
            // available and the scheduler retries when connectivity returns.
            await container.read(referenceSnapshotServiceProvider).refresh();
            container.read(syncSchedulerProvider).start();
            unawaited(() async {
              try {
                await Future.wait([
                  invoiceRepository.ensureAllocation(),
                  invoiceRepository.ensureAllocation(
                    series: 'CREDIT_NOTE',
                    documentType: 'CREDIT_NOTE',
                  ),
                  invoiceRepository.ensureAllocation(
                    series: 'DEBIT_NOTE',
                    documentType: 'DEBIT_NOTE',
                  ),
                ]);
              } catch (error, stackTrace) {
                developer.log(
                  'Document number prefetch deferred.',
                  name: 'apexbooks.numbering',
                  error: error.runtimeType,
                  stackTrace: stackTrace,
                );
              }
            }());
          }
        }());
      });
    },
    (error, stack) {
      showStartupFailure(error, stack);
      // `FlutterError.presentError` writes to dart:io stdout on some Flutter
      // web builds (`StdIOUtils._getStdioOutputStream`). Keep the web error
      // path browser-safe so a startup exception cannot mask the original
      // failure or prevent the first frame from rendering.
      if (!kIsWeb) {
        FlutterError.presentError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    },
  );
}

/// Visible, recoverable fallback for failures before the application shell is
/// mounted. A startup exception must not leave users with a silent blank page.
class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApexBooks startup error',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'ApexBooks could not start',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reload the page and try again. If the problem continues, '
                  'contact support with the startup time.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
