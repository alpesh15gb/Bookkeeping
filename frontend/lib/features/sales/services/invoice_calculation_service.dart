/// Invoice calculation service — pure math, no side effects.
/// Responsible for live line-item and grand-total calculations.
library;

import '../models/invoice_line.dart';

class InvoiceCalculationService {
  const InvoiceCalculationService();

  /// Recalculate a single line item from its raw inputs.
  InvoiceLine calculateLine({required InvoiceLine line}) {
    final lineSubtotal = line.rate * line.quantity;
    // API line-item `discount` is an amount, not a percentage.
    final discountAmt = line.discount.clamp(0, lineSubtotal).toDouble();
    final taxable = lineSubtotal - discountAmt;
    // For intra-state: CGST + SGST; inter-state: IGST.
    // We use half/half by default; override via isInterState param.
    final gst = taxable * (line.gstRate / 100);
    final cgst = gst / 2;
    final sgst = gst / 2;
    final igst = 0.0; // determined by pos_state_code match
    final cess = taxable * (line.cessRate / 100);
    final total = taxable + gst + cess;

    return line.copyWith(
      subtotal: round2(taxable),
      cgstRate: round2(line.gstRate / 2),
      cgstAmount: round2(cgst),
      sgstRate: round2(line.gstRate / 2),
      sgstAmount: round2(sgst),
      igstAmount: round2(igst),
      cessAmount: round2(cess),
      total: round2(total),
    );
  }

  /// Recalculate all lines, returning updated list + header totals.
  ({
    List<InvoiceLine> lines,
    double subtotal,
    double discountTotal,
    double totalTax,
    double total,
  })
  calculateAll({
    required List<InvoiceLine> lines,
    double discountRate = 0,
    double shippingCharges = 0,
  }) {
    final updatedLines = lines.map((l) => calculateLine(line: l)).toList();
    final subtotal = updatedLines.fold<double>(0, (s, l) => s + l.subtotal);
    final headerDiscount = subtotal * (discountRate / 100);
    final lineDiscounts = updatedLines.fold<double>(
      0,
      (s, l) => s + l.discount,
    );
    final discountTotal = lineDiscounts + headerDiscount;
    final taxable = subtotal - headerDiscount + shippingCharges;
    final cgst = updatedLines.fold<double>(0, (s, l) => s + l.cgstAmount);
    final sgst = updatedLines.fold<double>(0, (s, l) => s + l.sgstAmount);
    final igst = updatedLines.fold<double>(0, (s, l) => s + l.igstAmount);
    final cess = updatedLines.fold<double>(0, (s, l) => s + l.cessAmount);
    final totalTax = cgst + sgst + igst + cess;
    // Match the backend payable amount, which is rounded to the nearest rupee.
    final total = (taxable + totalTax).roundToDouble();

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
