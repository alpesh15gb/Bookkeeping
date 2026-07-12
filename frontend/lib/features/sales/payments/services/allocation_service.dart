/// Pure allocation engine — all math, no UI or API dependencies.
///
/// Given a set of outstanding invoices and a payment amount,
/// suggests allocations by oldest due date first.
library;

import '../models/payment_models.dart';
import '../models/outstanding_invoice.dart';

class AllocationService {
  const AllocationService();

  /// Suggest allocations for a payment across outstanding invoices.
  ///
  /// Rules:
  /// - Oldest due date first
  /// - Never exceed outstanding balance per invoice
  /// - Never allocate negative amounts
  /// - Excess payment amount remains unallocated (returned as surplus)
  ({List<PaymentAllocation> allocations, double surplus}) suggestAllocations({
    required double paymentAmount,
    required List<OutstandingInvoice> invoices,
  }) {
    if (paymentAmount <= 0 || invoices.isEmpty) {
      return (allocations: const [], surplus: paymentAmount);
    }

    // Sort by due date ascending (oldest first)
    final sorted = List<OutstandingInvoice>.from(invoices)
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final result = <PaymentAllocation>[];
    var remaining = paymentAmount;

    for (final inv in sorted) {
      if (remaining <= 0 || inv.outstanding <= 0) continue;
      final allocate = (remaining < inv.outstanding)
          ? remaining
          : inv.outstanding;
      result.add(
        PaymentAllocation(
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber,
          amount: allocate,
        ),
      );
      remaining -= allocate;
    }

    return (allocations: result, surplus: remaining);
  }

  /// Validate a single allocation amount against invoice outstanding.
  (bool valid, String? error) validateAllocationAmount({
    required double invoiceTotal,
    required double alreadyPaid,
    required double allocationAmount,
  }) {
    if (allocationAmount <= 0) {
      return (false, 'Allocation must be greater than zero');
    }
    final outstanding = (invoiceTotal - alreadyPaid).clamp(0, double.infinity);
    if (allocationAmount > outstanding) {
      return (
        false,
        'Allocation (${allocationAmount.toStringAsFixed(2)}) exceeds outstanding (${outstanding.toStringAsFixed(2)})',
      );
    }
    return (true, null);
  }

  /// Get outstanding balance for an invoice.
  double getOutstanding(double total, double amountPaid) =>
      (total - amountPaid).clamp(0, double.infinity);

  /// Check if a set of allocations sum correctly within payment amount.
  (bool valid, String? error) validateAllocationsSum({
    required double paymentAmount,
    required List<PaymentAllocation> allocations,
  }) {
    final totalAllocated = allocations.fold<double>(0, (s, a) => s + a.amount);
    if (totalAllocated <= 0) {
      return (false, 'At least one allocation is required');
    }
    if (totalAllocated > paymentAmount) {
      return (
        false,
        'Total allocated ($totalAllocated) exceeds payment amount ($paymentAmount)',
      );
    }
    return (true, null);
  }

  /// Prevent duplicate invoice allocation.
  (bool valid, String? error) preventDuplicateInvoice({
    required List<PaymentAllocation> allocations,
    required String invoiceId,
  }) {
    if (allocations.any((a) => a.invoiceId == invoiceId)) {
      final short = invoiceId.length > 8
          ? invoiceId.substring(0, 8)
          : invoiceId;
      return (false, 'Invoice $short is already allocated');
    }
    return (true, null);
  }
}
