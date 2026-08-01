/// Repository interface for payments.
library;

import '../entities/payment_entity.dart';
import '../commands/payment_commands.dart';

abstract interface class PaymentRepository {
  Stream<List<PaymentEntity>> watchPayments({String? companyId});
  Future<PaymentEntity?> getPayment(String localId);

  /// Save a draft payment — no journal or outbox created.
  Future<PaymentEntity> saveDraft(SavePaymentDraftCommand command);

  /// Post a payment: create journal + outbox atomically.
  Future<PaymentEntity> post(PostPaymentCommand command);

  Future<void> retrySync(String localId);
}
