/// Read-only repository for /masters/payment-terms.
library;

import 'package:dio/dio.dart';
import 'package:apexbooks/core/api/base_repository.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import '../models/payment_term.dart';

class PaymentTermRepository extends BaseRepository<PaymentTerm> {
  PaymentTermRepository(Dio dio, CacheService cache) : super(dio, cache);

  @override
  String get path => '/masters/payment-terms';
  @override
  String get cachePrefix => 'payment-terms';
  @override
  PaymentTerm parseOne(Map<String, dynamic> json) =>
      const PaymentTerm(id: '').fromJson(json);
}
