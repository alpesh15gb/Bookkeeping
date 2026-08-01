/// Contact controller.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import '../data/models/contact.dart';
import '../data/repositories/contact_repository.dart';

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return ContactRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

final contactControllerProvider =
    StateNotifierProvider<ContactController, ListState>((ref) {
      return ContactController(
        ref.watch(contactRepositoryProvider),
        ref.watch(notificationServiceProvider),
      );
    });

class ContactController extends BaseCrudController<Contact> {
  ContactController(ContactRepository super.repo, super.notif);
}
