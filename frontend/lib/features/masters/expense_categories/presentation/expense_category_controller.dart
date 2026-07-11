/// Expense Category controller.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import '../data/models/expense_category.dart';
import '../data/repositories/expense_category_repository.dart';

final expenseCategoryRepositoryProvider = Provider<ExpenseCategoryRepository>((
  ref,
) {
  return ExpenseCategoryRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheServiceProvider),
  );
});

final expenseCategoryControllerProvider =
    StateNotifierProvider<ExpenseCategoryController, ListState>((ref) {
      return ExpenseCategoryController(
        ref.watch(expenseCategoryRepositoryProvider),
        ref.watch(notificationServiceProvider),
      );
    });

class ExpenseCategoryController extends BaseCrudController<ExpenseCategory> {
  ExpenseCategoryController(
    ExpenseCategoryRepository repo,
    NotificationService notif,
  ) : super(repo, notif);
}
