/// Three-way matching service — PO ↔ Goods Receipt ↔ Vendor Bill.
///
/// Validates quantity, amount, and price variance before a bill can be
/// finalized. This is the strongest procurement control.
library;

import '../models/match_models.dart';

class ThreeWayMatchingService {
  const ThreeWayMatchingService();

  /// Run a three-way match across line items.
  ///
  /// Rules enforced:
  ///  - Billed quantity cannot exceed received quantity (over-billing).
  ///  - Missing receipt (billed without receipt) is an error.
  ///  - Price variance beyond 1% tolerance is a warning.
  ///  - Total billed amount cannot exceed PO total.
  MatchResult match({
    required double poTotal,
    required List<LineMatchInput> lines,
  }) {
    final discrepancies = <MatchDiscrepancy>[];
    var totalReceived = 0.0;
    var totalBilledQty = 0.0;
    var totalBilledAmt = 0.0;

    for (final line in lines) {
      totalReceived += line.receivedQuantity;
      totalBilledQty += line.billedQuantity;
      totalBilledAmt += line.billedLineTotal;

      // Missing receipt: billed without being received.
      if (line.billedQuantity > 0 && line.receivedQuantity <= 0) {
        discrepancies.add(
          MatchDiscrepancy(
            field: 'quantity_${line.productId}',
            message:
                'Billed quantity for ${line.productId} has no '
                'corresponding goods receipt',
            severity: MatchDiscrepancySeverity.error,
            billValue: line.billedQuantity,
            receiptValue: line.receivedQuantity,
          ),
        );
      }

      // Over-billing: billed quantity exceeds received.
      if (line.isOverBilled) {
        discrepancies.add(
          MatchDiscrepancy(
            field: 'quantity_${line.productId}',
            message:
                'Billed quantity (${line.billedQuantity}) exceeds received '
                'quantity (${line.receivedQuantity}) for ${line.productId}',
            severity: MatchDiscrepancySeverity.error,
            receiptValue: line.receivedQuantity,
            billValue: line.billedQuantity,
          ),
        );
      }

      // Under-billing: partial billing is allowed but flagged as info.
      if (line.isUnderBilled && line.billedQuantity > 0) {
        discrepancies.add(
          MatchDiscrepancy(
            field: 'quantity_${line.productId}',
            message:
                'Partial billing: billed ${line.billedQuantity} of received '
                '${line.receivedQuantity} for ${line.productId}',
            severity: MatchDiscrepancySeverity.info,
            receiptValue: line.receivedQuantity,
            billValue: line.billedQuantity,
          ),
        );
      }

      // Price variance beyond tolerance.
      if (line.isPriceVariance) {
        final variancePct =
            ((line.billedRate - line.poRate).abs() / line.poRate * 100);
        discrepancies.add(
          MatchDiscrepancy(
            field: 'rate_${line.productId}',
            message:
                'Price variance of ${variancePct.toStringAsFixed(1)}% '
                'between PO (${line.poRate}) and bill (${line.billedRate}) '
                'for ${line.productId}',
            severity: MatchDiscrepancySeverity.warning,
            poValue: line.poRate,
            billValue: line.billedRate,
          ),
        );
      }
    }

    // Total billed amount cannot exceed PO total.
    if (totalBilledAmt > poTotal + 0.01) {
      discrepancies.add(
        MatchDiscrepancy(
          field: 'total_amount',
          message:
              'Total billed amount ($totalBilledAmt) exceeds PO total '
              '($poTotal)',
          severity: MatchDiscrepancySeverity.error,
          poValue: poTotal,
          billValue: totalBilledAmt,
        ),
      );
    }

    final hasErrors = discrepancies.any((d) => d.isError);
    return MatchResult(
      isMatched: !hasErrors,
      discrepancies: discrepancies,
      poTotal: poTotal,
      receivedQuantity: totalReceived,
      billedQuantity: totalBilledQty,
      billedAmount: totalBilledAmt,
    );
  }

  /// Quick two-way match (PO ↔ Bill) when goods receipt is not used.
  MatchResult twoWayMatch({
    required double poTotal,
    required List<LineMatchInput> lines,
  }) {
    // For two-way matching, treat received quantity as equal to billed
    // quantity (i.e., skip receipt validation).
    final adjustedLines = lines
        .map(
          (l) => LineMatchInput(
            productId: l.productId,
            poQuantity: l.poQuantity,
            poRate: l.poRate,
            receivedQuantity: l.billedQuantity,
            billedQuantity: l.billedQuantity,
            billedRate: l.billedRate,
          ),
        )
        .toList();
    return match(poTotal: poTotal, lines: adjustedLines);
  }
}
