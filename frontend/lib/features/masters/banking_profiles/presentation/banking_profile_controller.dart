/// Banking Profile controller.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import '../data/models/banking_profile.dart';
import '../data/repositories/banking_profile_repository.dart';

final bankingProfileRepositoryProvider = Provider<BankingProfileRepository>((
  ref,
) {
  return BankingProfileRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

final bankingProfileControllerProvider =
    StateNotifierProvider<BankingProfileController, ListState>((ref) {
      return BankingProfileController(
        ref.watch(bankingProfileRepositoryProvider),
        ref.watch(notificationServiceProvider),
      );
    });

class BankingProfileController extends BaseCrudController<BankingProfile> {
  BankingProfileController(
    BankingProfileRepository repo,
    NotificationService notif,
  ) : super(repo, notif);
}
