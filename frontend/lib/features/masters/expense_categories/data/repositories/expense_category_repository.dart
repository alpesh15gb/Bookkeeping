/// Repository for /masters/expense-categories.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../models/expense_category.dart';

class ExpenseCategoryRepository extends BaseRepository<ExpenseCategory> {
  ExpenseCategoryRepository(Dio dio, CacheService cache) : super(dio, cache);

  @override
  String get path => '/masters/expense-categories';
  @override
  String get cachePrefix => 'expense-categories';
  @override
  ExpenseCategory parseOne(Map<String, dynamic> json) =>
      const ExpenseCategory(id: '').fromJson(json);
}
