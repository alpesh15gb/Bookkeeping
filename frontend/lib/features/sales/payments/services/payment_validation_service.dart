/// Payment validation service — business rules for receipts.
library;

import '../models/payment_models.dart';
import '../models/outstanding_invoice.dart';
import '../models/payment_enums.dart';

class PaymentValidationService {
  const PaymentValidationService();

  /// Validate the entire payment receipt before submission.
  (bool valid, String? error) validateForCreate({
    required String? contactId,
    required String paymentDate,
    required String paymentMode,
    required double amount,
    required List<PaymentAllocation> allocations,
    required List<OutstandingInvoice> availableInvoices,
  }) {
    if (contactId == null || contactId.isEmpty) {
      return (false, 'Customer is required');
    }
    if (paymentDate.isEmpty) {
      return (false, 'Payment date is required');
    }
    if (amount <= 0) {
      return (false, 'Amount must be greater than zero');
    }
    if (allocations.isEmpty) {
      return (false, 'At least one allocation is required');
    }

    final modeValid = PaymentMode.values.any(
      (m) => m.value == paymentMode.toUpperCase(),
    );
    if (!modeValid) {
      return (false, 'Invalid payment mode: $paymentMode');
    }

    // Validate each allocation
    for (final alloc in allocations) {
      if (alloc.amount <= 0) {
        return (false, 'Allocation amount must be greater than zero');
      }
      // Find matching invoice
      final inv = availableInvoices
          .where((i) => i.id == alloc.invoiceId)
          .firstOrNull;
      if (inv == null) {
        return (false, 'Invoice not found for allocation');
      }
      if (alloc.amount > inv.outstanding) {
        return (
          false,
          'Allocation (${alloc.amount}) exceeds outstanding (${inv.outstanding}) for invoice ${inv.invoiceNumber}',
        );
      }
    }

    // Total allocated <= payment amount
    final totalAllocated = allocations.fold<double>(0, (s, a) => s + a.amount);
    if (totalAllocated > amount) {
      return (
        false,
        'Total allocated ($totalAllocated) exceeds payment amount ($amount)',
      );
    }

    return (true, null);
  }

  /// Validate payment cancellation.
  (bool valid, String? error) validateCancel(Payment payment) {
    if (payment.status == PaymentStatus.cancelled) {
      return (false, 'Payment is already cancelled');
    }
    if (!payment.status.isCancellable) {
      return (false, 'Payment cannot be cancelled in current state');
    }
    return (true, null);
  }
}
