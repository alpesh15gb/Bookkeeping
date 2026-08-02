/// Invoice calculation service — pure math, no side effects.
/// Responsible for live line-item and grand-total calculations.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/invoice_line.dart';

class InvoiceCalculationService {
  const InvoiceCalculationService();

  /// Recalculate a single line item from its raw inputs.
  InvoiceLine calculateLine({
    required InvoiceLine line,
    bool isInterState = false,
    bool isGstInclusive = false,
  }) {
    final lineSubtotal = line.rate * line.quantity;
    // API line-item `discount` is an amount, not a percentage.
    final discountAmt = line.discount.clamp(0, lineSubtotal).toDouble();
    final discounted = lineSubtotal - discountAmt;
    final taxable = isGstInclusive && line.gstRate > 0
        ? discounted / (1 + line.gstRate / 100)
        : discounted;
    // For intra-state: CGST + SGST; inter-state: IGST.
    // We use half/half by default; override via isInterState param.
    final gst = taxable * (line.gstRate / 100);
    final cgst = isInterState ? 0.0 : gst / 2;
    final sgst = isInterState ? 0.0 : gst / 2;
    final igst = isInterState ? gst : 0.0;
    final cess = taxable * (line.cessRate / 100);
    final total = taxable + gst + cess;

    return line.copyWith(
      subtotal: round2(taxable),
      cgstRate: round2(isInterState ? 0 : line.gstRate / 2),
      cgstAmount: round2(cgst),
      sgstRate: round2(isInterState ? 0 : line.gstRate / 2),
      sgstAmount: round2(sgst),
      igstRate: round2(isInterState ? line.gstRate : 0),
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
    bool isInterState = false,
    bool isGstInclusive = false,
    bool isRcm = false,
  }) {
    final updatedLines = lines
        .map(
          (l) => calculateLine(
            line: l,
            isInterState: isInterState,
            isGstInclusive: isGstInclusive,
          ),
        )
        .toList();
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
    final total = (taxable + (isRcm ? 0 : totalTax)).roundToDouble();

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

/// Provider for invoice calculation service.
final invoiceCalculationServiceProvider = Provider<InvoiceCalculationService>((ref) {
  return const InvoiceCalculationService();
});
