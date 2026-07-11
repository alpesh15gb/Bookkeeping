/// Three-way matching models.
library;

import 'package:flutter/foundation.dart';

/// Severity of a matching discrepancy.
enum MatchDiscrepancySeverity { info, warning, error }

/// A single discrepancy found during three-way matching.
@immutable
class MatchDiscrepancy {
  const MatchDiscrepancy({
    required this.field,
    required this.message,
    required this.severity,
    this.poValue,
    this.receiptValue,
    this.billValue,
  });

  final String field;
  final String message;
  final MatchDiscrepancySeverity severity;
  final double? poValue;
  final double? receiptValue;
  final double? billValue;

  bool get isError => severity == MatchDiscrepancySeverity.error;
  bool get isWarning => severity == MatchDiscrepancySeverity.warning;
}

/// Result of a three-way match between PO, Goods Receipt, and Vendor Bill.
@immutable
class MatchResult {
  const MatchResult({
    required this.isMatched,
    required this.discrepancies,
    required this.poTotal,
    required this.receivedQuantity,
    required this.billedQuantity,
    required this.billedAmount,
  });

  final bool isMatched;
  final List<MatchDiscrepancy> discrepancies;
  final double poTotal;
  final double receivedQuantity;
  final double billedQuantity;
  final double billedAmount;

  bool get hasErrors => discrepancies.any((d) => d.isError);
  bool get hasWarnings => discrepancies.any((d) => d.isWarning);

  /// A bill can be finalized only if there are no error-severity discrepancies.
  bool get canFinalize => !hasErrors;

  List<MatchDiscrepancy> get errors =>
      discrepancies.where((d) => d.isError).toList();
  List<MatchDiscrepancy> get warnings =>
      discrepancies.where((d) => d.isWarning).toList();
}

/// Per-line comparison data for three-way matching.
@immutable
class LineMatchInput {
  const LineMatchInput({
    required this.productId,
    required this.poQuantity,
    required this.poRate,
    required this.receivedQuantity,
    required this.billedQuantity,
    required this.billedRate,
  });

  final String productId;
  final double poQuantity;
  final double poRate;
  final double receivedQuantity;
  final double billedQuantity;
  final double billedRate;

  double get poLineTotal => poQuantity * poRate;
  double get billedLineTotal => billedQuantity * billedRate;
  bool get quantityMatches => (billedQuantity - receivedQuantity).abs() < 0.01;
  bool get isOverBilled => billedQuantity > receivedQuantity + 0.01;
  bool get isUnderBilled => billedQuantity < receivedQuantity - 0.01;
  bool get priceMatches => (billedRate - poRate).abs() < 0.01;
  bool get isPriceVariance =>
      poRate > 0 && ((billedRate - poRate).abs() / poRate) > 0.01;
}
