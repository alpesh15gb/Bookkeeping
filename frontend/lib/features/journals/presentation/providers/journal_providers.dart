/// Riverpod providers for the offline-first journal feature.
///
/// These providers wire up the [JournalRepository] using the local database
/// and sync engine.  All reads come from local SQLite; all writes go through
/// the repository which queues sync operations atomically.
///
/// The [journalRepositoryProvider] replaces the old [journalServiceProvider]
/// (which is still available for direct API access during development).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../features/auth/presentation/auth_controller.dart';
import '../../../journals/data/local/journal_local_data_source.dart';
import '../../../journals/data/repositories/journal_repository_impl.dart';
import '../../../journals/domain/entities/journal_entity.dart';
import '../../../journals/domain/repositories/journal_repository.dart';

// ── Local data source ─────────────────────────────────────────────────────────

final journalLocalDataSourceProvider = Provider<JournalLocalDataSource>((ref) {
  return JournalLocalDataSource(ref.watch(databaseProvider));
});

// ── Repository ────────────────────────────────────────────────────────────────

/// Provides the active [JournalRepository] backed by local SQLite.
///
/// This is the entry point for all journal reads and writes throughout the app.
final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final localDs = ref.watch(journalLocalDataSourceProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final dio = ref.watch(apiClientProvider);

  // Derive companyId and actorId from the active auth context.
  Future<String> companyIdProvider() async {
    final auth = ref.read(authControllerProvider);
    return auth.activeMembership?.tenantId ?? '';
  }

  Future<String> actorIdProvider() async {
    final auth = ref.read(authControllerProvider);
    return auth.user?.id ?? '';
  }

  // Device ID is stored in secure storage — wired in main.dart via provider.
  Future<String> deviceIdProvider() async {
    return ref.read(deviceIdProvider_);
  }

  return JournalRepositoryImpl(
    db: db,
    localDs: localDs,
    syncEngine: syncEngine,
    dio: dio,
    deviceIdProvider: deviceIdProvider,
    companyIdProvider: companyIdProvider,
    actorIdProvider: actorIdProvider,
  );
});

// ── Device ID (provisioned in main.dart) ──────────────────────────────────────

/// Provides the stable device UUID for this installation.
///
/// Override this in `main()` after reading from [FlutterSecureStorage].
final deviceIdProvider_ = Provider<String>((ref) {
  throw UnimplementedError(
    'deviceIdProvider_ must be overridden in main() with the actual device UUID.',
  );
});

// ── List stream ───────────────────────────────────────────────────────────────

/// Reactive list of all journal entries for the current company.
///
/// Replaces the old [journalsListProvider] (FutureProvider → remote API).
/// This stream is backed by Drift and emits a new list whenever any
/// journal row changes.
final journalsStreamProvider =
    StreamProvider.autoDispose<List<JournalEntryEntity>>((ref) {
      return ref.watch(journalRepositoryProvider).watchJournals();
    });

/// Filtered journals — pass a [JournalFilter] to narrow the results.
final filteredJournalsProvider = StreamProvider.autoDispose
    .family<List<JournalEntryEntity>, JournalFilter>((ref, filter) {
      return ref.watch(journalRepositoryProvider).watchJournals(filter: filter);
    });
