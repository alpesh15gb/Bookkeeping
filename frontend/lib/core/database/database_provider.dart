/// Riverpod provider for [AppDatabase].
///
/// Override this in `main()` by passing a real (or test) database instance:
///
/// ```dart
/// ProviderContainer(overrides: [
///   databaseProvider.overrideWithValue(AppDatabase()),
/// ]);
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

export 'app_database.dart';

/// The singleton [AppDatabase] instance for this application session.
///
/// This provider **must** be overridden before use — the default throws.
/// The override is set in `main()` after platform initialisation is complete.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider has not been initialised. '
    'Override it inside ProviderContainer in main() before calling runApp().',
  );
});
