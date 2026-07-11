/// Valuation service — calculates inventory value and unit costs.
///
/// Kept separate from stock movement logic so different valuation methods
/// can be supported without changing movement code.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported valuation methods.
enum ValuationMethod {
  simpleAverage('SIMPLE_AVERAGE'),
  fifo('FIFO'),
  weightedAverage('WEIGHTED_AVERAGE'),
  standardCost('STANDARD_COST');

  const ValuationMethod(this.value);
  final String value;
}

/// Result of a valuation calculation.
class ValuationResult {
  const ValuationResult({
    required this.productId,
    this.productName = '',
    this.currentStock = 0,
    this.unitCost = 0,
    this.totalValue = 0,
    this.method = ValuationMethod.simpleAverage,
  });

  final String productId;
  final String productName;
  final double currentStock;
  final double unitCost;
  final double totalValue;
  final ValuationMethod method;
}

/// Pure valuation engine — no UI or API dependency.
class ValuationService {
  const ValuationService();

  /// Calculate the simple average unit cost from a list of stock movements.
  double calculateAverageCost({
    required List<double> quantities,
    required List<double> rates,
  }) {
    if (quantities.isEmpty || rates.isEmpty) return 0;
    double totalQty = 0;
    double totalValue = 0;
    for (var i = 0; i < quantities.length; i++) {
      totalQty += quantities[i].abs();
      totalValue += quantities[i].abs() * rates[i];
    }
    return totalQty > 0 ? totalValue / totalQty : 0;
  }

  /// Calculate stock value at a given unit cost.
  double calculateStockValue({
    required double quantity,
    required double unitCost,
  }) => quantity * unitCost;

  /// Calculate moving weighted average (new average after a purchase).
  double calculateWeightedAverage({
    required double currentQuantity,
    required double currentAvgCost,
    required double newQuantity,
    required double newUnitCost,
  }) {
    final currentValue = currentQuantity * currentAvgCost;
    final newValue = newQuantity * newUnitCost;
    final totalQty = currentQuantity + newQuantity;
    return totalQty > 0 ? (currentValue + newValue) / totalQty : 0;
  }

  /// Compute valuation result for a product.
  ValuationResult computeValuation({
    required String productId,
    required String productName,
    required double currentStock,
    required double unitCost,
    ValuationMethod method = ValuationMethod.simpleAverage,
  }) {
    final totalValue = calculateStockValue(
      quantity: currentStock,
      unitCost: unitCost,
    );
    return ValuationResult(
      productId: productId,
      productName: productName,
      currentStock: currentStock,
      unitCost: unitCost,
      totalValue: totalValue,
      method: method,
    );
  }
}

final valuationServiceProvider = Provider<ValuationService>((ref) {
  return const ValuationService();
});
