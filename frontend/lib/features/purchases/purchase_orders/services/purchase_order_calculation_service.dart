/// Purchase order calculation service — pure math, mirrors invoice calc.
library;

import '../models/purchase_order_line.dart';

class PurchaseOrderCalculationService {
  const PurchaseOrderCalculationService();

  /// Recalculate a single line item from its raw inputs.
  PurchaseOrderLine calculateLine({required PurchaseOrderLine line}) {
    final lineSubtotal = line.rate * line.quantity;
    final discountAmt = lineSubtotal * (line.discount / 100);
    final taxable = lineSubtotal - discountAmt;
    final gst = taxable * (line.gstRate / 100);
    final cgst = gst / 2;
    final sgst = gst / 2;
    final cess = taxable * (line.cessRate / 100);
    final total = taxable + gst + cess;

    return line.copyWith(
      subtotal: round2(lineSubtotal),
      cgstRate: round2(line.gstRate / 2),
      cgstAmount: round2(cgst),
      sgstRate: round2(line.gstRate / 2),
      sgstAmount: round2(sgst),
      igstAmount: round2(0),
      cessAmount: round2(cess),
      total: round2(total),
    );
  }

  /// Recalculate all lines, returning updated list + header totals.
  ({
    List<PurchaseOrderLine> lines,
    double subtotal,
    double discountTotal,
    double totalTax,
    double total,
  })
  calculateAll({required List<PurchaseOrderLine> lines}) {
    final updatedLines = lines.map((l) => calculateLine(line: l)).toList();
    final subtotal = updatedLines.fold<double>(0, (s, l) => s + l.subtotal);
    final discountTotal = updatedLines.fold<double>(
      0,
      (s, l) => s + l.discountAmount,
    );
    final totalTax = updatedLines.fold<double>(
      0,
      (s, l) =>
          s +
          l.cgstAmount +
          l.sgstAmount +
          l.igstAmount +
          l.utgstAmount +
          l.cessAmount,
    );
    final total = updatedLines.fold<double>(0, (s, l) => s + l.total);
    return (
      lines: updatedLines,
      subtotal: round2(subtotal),
      discountTotal: round2(discountTotal),
      totalTax: round2(totalTax),
      total: round2(total),
    );
  }

  double round2(double v) => (v * 100).roundToDouble() / 100;
}
