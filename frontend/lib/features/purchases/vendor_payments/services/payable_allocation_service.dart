/// Payable allocation service — pure engine, mirrors AllocationService.
///
/// Suggests allocations by oldest due-date first, and validates that
/// allocations do not exceed outstanding balances or payment amount.
library;

import '../models/outstanding_bill.dart';
import '../models/vendor_payment.dart';

class PayableAllocationService {
  const PayableAllocationService();

  /// Suggest allocations for a payment across outstanding bills.
  /// Allocation follows oldest-due-date first.
  List<PaymentAllocation> suggestAllocations({
    required List<OutstandingBill> bills,
    required double paymentAmount,
  }) {
    final sorted = [...bills]
      ..sort((a, b) {
        // Overdue first, then by due date ascending.
        final aOver = a.isOverdue ? 0 : 1;
        final bOver = b.isOverdue ? 0 : 1;
        final cmp = aOver.compareTo(bOver);
        if (cmp != 0) return cmp;
        return a.dueDate.compareTo(b.dueDate);
      });

    final allocations = <PaymentAllocation>[];
    var remaining = paymentAmount;

    for (final bill in sorted) {
      if (remaining <= 0) break;
      if (bill.outstanding <= 0) continue;
      final alloc = remaining > bill.outstanding ? bill.outstanding : remaining;
      allocations.add(
        PaymentAllocation(
          billId: bill.id,
          billNumber: bill.billNumber,
          amount: alloc,
        ),
      );
      remaining -= alloc;
    }
    return allocations;
  }

  /// Validate a set of allocations against outstanding bills.
  /// Returns `null` if valid, or an error message.
  String? validateAllocations({
    required List<OutstandingBill> bills,
    required List<PaymentAllocation> allocations,
    required double paymentAmount,
  }) {
    if (allocations.isEmpty) {
      return 'At least one allocation is required';
    }

    final totalAllocated = allocations.fold<double>(0, (s, a) => s + a.amount);
    if (totalAllocated > paymentAmount + 0.01) {
      return 'Total allocated ($totalAllocated) exceeds payment amount ($paymentAmount)';
    }

    final billMap = {for (final b in bills) b.id: b};
    for (final alloc in allocations) {
      final bill = billMap[alloc.billId];
      if (bill == null) {
        return 'Allocation references unknown bill ${alloc.billId}';
      }
      if (alloc.amount <= 0) {
        return 'Allocation amount must be greater than zero';
      }
      if (alloc.amount > bill.outstanding + 0.01) {
        return 'Allocation (${alloc.amount}) exceeds outstanding balance '
            '(${bill.outstanding}) for bill ${bill.billNumber}';
      }
    }
    return null;
  }

  /// Sum of allocation amounts.
  double totalAllocated(List<PaymentAllocation> allocations) =>
      allocations.fold<double>(0, (s, a) => s + a.amount);

  /// Compute the unallocated portion of a payment.
  double unallocatedAmount({
    required double paymentAmount,
    required List<PaymentAllocation> allocations,
  }) => (paymentAmount - totalAllocated(allocations)).clamp(0, double.infinity);
}
