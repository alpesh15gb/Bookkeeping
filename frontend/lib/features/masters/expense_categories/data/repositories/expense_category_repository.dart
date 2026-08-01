/// Repository for /masters/expense-categories.
library;

import 'package:apexbooks/core/api/base_repository.dart';
import '../models/expense_category.dart';

class ExpenseCategoryRepository extends BaseRepository<ExpenseCategory> {
  ExpenseCategoryRepository(super.dio, super.cache);

  @override
  String get path => '/masters/expense-categories';
  @override
  String get cachePrefix => 'expense-categories';
  @override
  ExpenseCategory parseOne(Map<String, dynamic> json) =>
      const ExpenseCategory(id: '').fromJson(json);
}
