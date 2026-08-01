/// Read-only repository for /masters/payment-terms.
library;

import 'package:apexbooks/core/api/base_repository.dart';
import '../models/payment_term.dart';

class PaymentTermRepository extends BaseRepository<PaymentTerm> {
  PaymentTermRepository(super.dio, super.cache);

  @override
  String get path => '/masters/payment-terms';
  @override
  String get cachePrefix => 'payment-terms';
  @override
  PaymentTerm parseOne(Map<String, dynamic> json) =>
      const PaymentTerm(id: '').fromJson(json);
}
