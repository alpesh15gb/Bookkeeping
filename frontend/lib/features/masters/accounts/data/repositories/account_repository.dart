/// Repository for /masters/accounts.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/account.dart';

class AccountRepository extends BaseRepository<Account> {
  AccountRepository(this._dio, CacheService cache) : super(_dio, cache);

  final Dio _dio;

  @override
  String get path => '/masters/accounts';
  @override
  String get cachePrefix => 'accounts';
  @override
  Account parseOne(Map<String, dynamic> json) =>
      const Account(id: '', name: '').fromJson(json);

  /// `POST /masters/accounts/seed-defaults` — bulk-create the standard
  /// chart of accounts for this tenant. Returns `{created, skipped, total}`.
  Future<Result<Map<String, dynamic>>> seedDefaults() {
    return guardDio(() async {
      final res = await _dio.post('$path/seed-defaults');
      return res.data as Map<String, dynamic>;
    });
  }
}
