/// Riverpod providers for the invoice UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/database/database_provider.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/sync/sync_providers.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'package:apexbooks/features/journals/presentation/providers/journal_providers.dart';
import 'package:apexbooks/features/invoices/data/repositories/invoice_repository_impl.dart';
import 'package:apexbooks/features/invoices/domain/repositories/invoice_repository.dart';

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final dio = ref.watch(apiClientProvider);

  Future<String> companyIdProvider() async {
    final auth = ref.read(authControllerProvider);
    return auth.activeMembership?.tenantId ?? '';
  }

  Future<String> actorIdProvider() async {
    final auth = ref.read(authControllerProvider);
    return auth.user?.id ?? '';
  }

  Future<String> deviceId() async => ref.read(deviceIdProvider_);
  Future<String> fyId() async {
    // For now return empty — resolved during issue command.
    return '';
  }

  return InvoiceRepositoryImpl(
    db: db,
    syncEngine: syncEngine,
    dio: dio,
    deviceIdProvider: deviceId,
    companyIdProvider: companyIdProvider,
    actorIdProvider: actorIdProvider,
    financialYearIdProvider: fyId,
  );
});
