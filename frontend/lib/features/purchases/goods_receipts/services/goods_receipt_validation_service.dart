/// Goods receipt validation service — over-receipt prevention.
library;

import '../models/goods_receipt.dart';
import '../models/goods_receipt_line.dart';

class GoodsReceiptValidationService {
  const GoodsReceiptValidationService();

  String? validateForConfirm(GoodsReceipt gr) {
    if (gr.receiptDate.isEmpty) return 'Receipt date is required';
    if (gr.purchaseOrderId.isEmpty) return 'Purchase order is required';
    if (gr.lines.isEmpty) return 'At least one receipt line is required';

    for (final line in gr.lines) {
      final err = validateLine(line);
      if (err != null) return err;
    }
    return null;
  }

  String? validateLine(GoodsReceiptLine line) {
    if (line.productId.isEmpty) return 'Product is required on all lines';
    if (line.quantityReceived <= 0) {
      return 'Received quantity must be greater than zero';
    }
    // Over-receipt prevention.
    if (line.isOverReceipt) {
      return 'Received quantity (${line.quantityReceived}) exceeds ordered '
          'quantity (${line.quantityOrdered}). Over-receipt is not allowed.';
    }
    return null;
  }

  /// Aggregate check: a goods receipt should not be confirmable if all lines
  /// have zero received quantity.
  String? validateHasReceivedQuantity(GoodsReceipt gr) {
    final totalReceived = gr.totalReceived;
    if (totalReceived <= 0) {
      return 'Cannot confirm a goods receipt with zero received quantity';
    }
    return null;
  }
}
