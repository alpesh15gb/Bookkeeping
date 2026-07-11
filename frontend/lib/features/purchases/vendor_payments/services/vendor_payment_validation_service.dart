/// Vendor payment validation service — mirrors PaymentValidationService.
library;

import '../models/vendor_payment.dart';
import '../models/vendor_payment_enums.dart';

class VendorPaymentValidationService {
  const VendorPaymentValidationService();

  String? validateForCreate(VendorPayment payment) {
    if (payment.contactId.isEmpty) return 'Vendor is required';
    if (payment.paymentNumber.isEmpty) return 'Payment number is required';
    if (payment.paymentDate.isEmpty) return 'Payment date is required';
    if (payment.amount <= 0) return 'Payment amount must be greater than zero';
    if (payment.allocations.isEmpty) {
      return 'At least one allocation is required';
    }

    final totalAllocated = payment.allocations.fold<double>(
      0,
      (s, a) => s + a.amount,
    );
    if (totalAllocated > payment.amount + 0.01) {
      return 'Total allocated ($totalAllocated) exceeds payment amount (${payment.amount})';
    }
    return null;
  }

  String? validateCancel(VendorPayment payment) {
    if (payment.status.isCancelled) {
      return 'Payment is already cancelled';
    }
    if (!payment.status.isCancellable) {
      return 'Only active payments can be cancelled';
    }
    return null;
  }

  String? validateTransition({
    required VendorPaymentStatus current,
    required VendorPaymentStatus target,
  }) {
    switch (current) {
      case VendorPaymentStatus.active:
        if (target == VendorPaymentStatus.cancelled) return null;
        return 'Active can only transition to Cancelled';
      case VendorPaymentStatus.cancelled:
        return 'Cancelled is a terminal state — no further transitions allowed';
    }
  }
}
