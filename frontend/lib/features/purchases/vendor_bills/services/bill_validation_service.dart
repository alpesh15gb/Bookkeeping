/// Bill validation service — mirrors InvoiceValidationService.
library;

import '../models/vendor_bill.dart';
import '../models/bill_line.dart';
import '../models/bill_status.dart';

class BillValidationService {
  const BillValidationService();

  /// Validate a bill before finalization/posting.
  String? validateForPost(VendorBill bill) {
    if (bill.billNumber.isEmpty) return 'Bill number is required';
    if (bill.contactId.isEmpty) return 'Vendor is required';
    if (bill.issueDate.isEmpty) return 'Issue date is required';
    if (bill.dueDate.isEmpty) return 'Due date is required';
    if (bill.lines.isEmpty) return 'At least one line item is required';
    if (bill.posStateCode.isEmpty) return 'POS state code is required';

    // Due date must not be before issue date.
    if (bill.dueDate.isNotEmpty &&
        bill.issueDate.isNotEmpty &&
        bill.dueDate.compareTo(bill.issueDate) < 0) {
      return 'Due date cannot be before issue date';
    }

    for (final line in bill.lines) {
      final err = validateLine(line);
      if (err != null) return err;
    }

    // TDS rate sanity check.
    if (bill.tdsRate < 0 || bill.tdsRate > 100) {
      return 'TDS rate must be between 0 and 100';
    }
    return null;
  }

  String? validateLine(BillLine line) {
    if (line.productId.isEmpty) return 'Product is required on all lines';
    if (line.quantity <= 0) return 'Quantity must be greater than zero';
    if (line.rate < 0) return 'Rate cannot be negative';
    if (line.gstRate < 0 || line.gstRate > 100) {
      return 'GST rate must be between 0 and 100';
    }
    if (line.hsnSac.isEmpty) return 'HSN/SAC is required on all lines';
    return null;
  }

  /// Validate a status transition. Returns `null` if allowed.
  String? validateTransition({
    required BillStatus current,
    required BillStatus target,
  }) {
    switch (current) {
      case BillStatus.draft:
        if (target == BillStatus.posted) return null;
        if (target == BillStatus.cancelled) return null;
        return 'Draft can only transition to Posted or Cancelled';
      case BillStatus.posted:
        if (target == BillStatus.cancelled) return null;
        return 'Posted can only transition to Cancelled';
      case BillStatus.unpaid:
        if (target == BillStatus.cancelled) return null;
        return 'Unpaid can only transition to Cancelled';
      case BillStatus.partiallyPaid:
        return 'Partially paid bills cannot be cancelled via simple transition';
      case BillStatus.paid:
        return 'Paid bills are terminal — no further transitions allowed';
      case BillStatus.cancelled:
        return 'Cancelled is a terminal state — no further transitions allowed';
    }
  }

  /// Validate the bill total balance check (mirrors backend ck_bills_total_balance).
  String? validateTotalBalance(VendorBill bill) {
    final computed =
        bill.subtotal +
        bill.cgstAmount +
        bill.sgstAmount +
        bill.igstAmount +
        bill.utgstAmount +
        bill.cessAmount +
        bill.roundOff -
        bill.discountTotal;
    final diff = (computed - bill.total).abs();
    if (diff > 0.02) {
      return 'Bill total does not balance: computed $computed vs stored ${bill.total}';
    }
    return null;
  }
}
