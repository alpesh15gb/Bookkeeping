/// Application-scoped providers for every local-first business repository.
///
/// Reading [offlineRepositoriesProvider] after authentication registers every
/// outbox pusher before the scheduler starts. This avoids operations remaining
/// permanently pending merely because a feature screen has not been opened.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/database_provider.dart';
import '../core/network/api_client.dart';
import '../core/sync/sync_providers.dart';
import 'auth/presentation/auth_controller.dart';
import 'banking/data/repositories/banking_repository_impl.dart';
import 'banking/domain/repositories/banking_repository.dart';
import 'credit_debit/data/repositories/credit_debit_repository_impl.dart';
import 'credit_debit/domain/repositories/credit_debit_repository.dart';
import 'inventory/data/repositories/inventory_repository_impl.dart';
import 'inventory/domain/repositories/inventory_repository.dart';
import 'journals/presentation/providers/journal_providers.dart';
import 'payments/data/repositories/payment_repository_impl.dart';
import 'payments/domain/repositories/payment_repository.dart';
import 'purchasing/data/repositories/purchasing_repository_impl.dart';
import 'purchasing/domain/repositories/purchasing_repository.dart';
import 'returns/data/repositories/returns_repository_impl.dart';
import 'returns/domain/repositories/returns_repository.dart';
import 'sales/data/repositories/sales_repository_impl.dart';
import 'sales/domain/repositories/sales_repository.dart';

Future<String> _companyId(Ref ref) async =>
    ref.read(authControllerProvider).activeMembership?.tenantId ?? '';

Future<String> _actorId(Ref ref) async =>
    ref.read(authControllerProvider).user?.id ?? '';

Future<String> _deviceId(Ref ref) async => ref.read(deviceIdProvider_);

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

final purchasingRepositoryProvider = Provider<PurchasingRepository>((ref) {
  return PurchasingRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

final returnsRepositoryProvider = Provider<ReturnsRepository>((ref) {
  return ReturnsRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

final creditDebitRepositoryProvider = Provider<CreditDebitRepository>((ref) {
  return CreditDebitRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

final bankingRepositoryProvider = Provider<BankingRepository>((ref) {
  return BankingRepositoryImpl(
    db: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
    dio: ref.watch(apiClientProvider),
    deviceIdProvider: () => _deviceId(ref),
    companyIdProvider: () => _companyId(ref),
    actorIdProvider: () => _actorId(ref),
  );
});

/// Eager bootstrap that guarantees all pusher registrations are installed.
final offlineRepositoriesProvider = Provider<void>((ref) {
  ref.watch(paymentRepositoryProvider);
  ref.watch(inventoryRepositoryProvider);
  ref.watch(purchasingRepositoryProvider);
  ref.watch(salesRepositoryProvider);
  ref.watch(returnsRepositoryProvider);
  ref.watch(creditDebitRepositoryProvider);
  ref.watch(bankingRepositoryProvider);
});
