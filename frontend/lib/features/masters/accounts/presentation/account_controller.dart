/// Account controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/account.dart';
import '../data/repositories/account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

final accountControllerProvider =
    StateNotifierProvider<AccountController, ListState>((ref) {
      return AccountController(
        ref.watch(accountRepositoryProvider),
        ref.watch(notificationServiceProvider),
      );
    });

class AccountController extends BaseCrudController<Account> {
  AccountController(this._accountRepo, this._notif)
    : super(_accountRepo, _notif);

  final AccountRepository _accountRepo;
  final NotificationService _notif;

  /// `POST /masters/accounts/seed-defaults`.
  /// Shows a success/error notification and reloads the list on success.
  Future<void> seedDefaults(BuildContext context) async {
    final result = await _accountRepo.seedDefaults();
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        _notif.success(
          context,
          'Seeded ${value['created']} standard accounts '
          '(${value['skipped']} already existed).',
        );
        // Reload with a generous limit to show the full seeded chart.
        await load(const ListQuery(limit: 1000));
      case Failure(:final error):
        _notif.error(context, error.message);
      case Loading():
        break;
    }
  }
}
