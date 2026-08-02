/// Pure validation engine for purchase orders — no UI or API dependencies.
library;

import '../models/purchase_order.dart';
import '../models/purchase_order_line.dart';
import '../models/purchase_order_status.dart';

class PurchaseOrderValidationService {
  const PurchaseOrderValidationService();

  /// Validate a PO before creation/submission.
  /// Returns `null` if valid, or an error message.
  String? validateForSubmit(PurchaseOrder po) {
    if (po.poNumber.isEmpty) return 'PO number is required';
    if (po.contactId.isEmpty) return 'Vendor is required';
    if (po.orderDate.isEmpty) return 'Order date is required';
    if (po.dueDate.isEmpty) return 'Due date is required';
    if (po.lines.isEmpty) return 'At least one line item is required';
    if (po.posStateCode.isEmpty) return 'POS state code is required';

    for (final line in po.lines) {
      final err = validateLine(line);
      if (err != null) return err;
    }
    return null;
  }

  String? validateLine(PurchaseOrderLine line) {
    if (line.productId.isEmpty) return 'Product is required on all lines';
    if (line.quantity <= 0) return 'Quantity must be greater than zero';
    if (line.rate < 0) return 'Rate cannot be negative';
    if (line.gstRate < 0 || line.gstRate > 100) {
      return 'GST rate must be between 0 and 100';
    }
    if (line.hsnSac.isEmpty) return 'HSN/SAC is required on all lines';
    return null;
  }

  /// Validate a state transition. Returns `null` if allowed.
  String? validateTransition({
    required PurchaseOrderStatus current,
    required PurchaseOrderStatus target,
  }) {
    switch (current) {
      case PurchaseOrderStatus.draft:
        if (target == PurchaseOrderStatus.pending ||
            target == PurchaseOrderStatus.approved ||
            target == PurchaseOrderStatus.confirmed) {
          return null;
        }
        if (target == PurchaseOrderStatus.cancelled) return null;
        return 'Draft can only transition to Pending, Approved, Confirmed or Cancelled';
      case PurchaseOrderStatus.pending:
        if (target == PurchaseOrderStatus.approved ||
            target == PurchaseOrderStatus.cancelled) {
          return null;
        }
        return 'Pending can only transition to Approved or Cancelled';
      case PurchaseOrderStatus.approved:
        if (target == PurchaseOrderStatus.confirmed ||
            target == PurchaseOrderStatus.partial ||
            target == PurchaseOrderStatus.completed) {
          return null;
        }
        return 'Approved can only transition to Confirmed, Partial or Completed';
      case PurchaseOrderStatus.confirmed:
        if (target == PurchaseOrderStatus.received ||
            target == PurchaseOrderStatus.partial ||
            target == PurchaseOrderStatus.completed ||
            target == PurchaseOrderStatus.cancelled) {
          return null;
        }
        return 'Confirmed can only transition to Received, Partial, Completed or Cancelled';
      case PurchaseOrderStatus.partial:
        if (target == PurchaseOrderStatus.completed) return null;
        return 'Partial can only transition to Completed';
      case PurchaseOrderStatus.received:
        return 'Received is a terminal state — no further transitions allowed';
      case PurchaseOrderStatus.completed:
        return 'Completed is a terminal state — no further transitions allowed';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled is a terminal state — no further transitions allowed';
    }
  }

  /// Validate that a receipt quantity does not exceed outstanding.
  String? validateReceiptQuantity({
    required double orderedQuantity,
    required double alreadyReceived,
    required double newReceipt,
  }) {
    if (newReceipt <= 0) return 'Receipt quantity must be greater than zero';
    final outstanding = orderedQuantity - alreadyReceived;
    if (newReceipt > outstanding + 0.001) {
      return 'Receipt quantity ($newReceipt) exceeds outstanding ($outstanding). Over-receipt is not allowed.';
    }
    return null;
  }
}
