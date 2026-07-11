// Tests for ValuationService — average cost, weighted average, stock value.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/inventory/valuation/services/valuation_service.dart';

void main() {
  const svc = ValuationService();

  group('calculateAverageCost', () {
    test('simple average', () {
      final avg = svc.calculateAverageCost(
        quantities: [10, 20, 30],
        rates: [100, 200, 300],
      );
      // Total value = 10*100 + 20*200 + 30*300 = 1000+4000+9000 = 14000
      // Total qty = 60
      // Average = 14000/60 = 233.333...
      expect(avg, closeTo(233.333, 0.01));
    });
    test('single entry', () {
      expect(svc.calculateAverageCost(quantities: [5], rates: [50]), 50);
    });
    test('empty returns 0', () {
      expect(svc.calculateAverageCost(quantities: [], rates: []), 0);
    });
    test('zero quantities returns 0', () {
      expect(
        svc.calculateAverageCost(quantities: [0, 0], rates: [100, 200]),
        0,
      );
    });
    test('uses absolute value of negative quantities (stock-out)', () {
      final avg = svc.calculateAverageCost(
        quantities: [10, -5],
        rates: [100, 100],
      );
      // 10*100 + 5*100 = 1500 / 15 = 100
      expect(avg, 100);
    });
  });

  group('calculateStockValue', () {
    test('quantity times unit cost', () {
      expect(svc.calculateStockValue(quantity: 50, unitCost: 20), 1000);
    });
    test('zero quantity', () {
      expect(svc.calculateStockValue(quantity: 0, unitCost: 100), 0);
    });
  });

  group('calculateWeightedAverage', () {
    test('no existing stock', () {
      final avg = svc.calculateWeightedAverage(
        currentQuantity: 0,
        currentAvgCost: 0,
        newQuantity: 10,
        newUnitCost: 100,
      );
      expect(avg, 100);
    });
    test('blends existing and new', () {
      final avg = svc.calculateWeightedAverage(
        currentQuantity: 20,
        currentAvgCost: 50,
        newQuantity: 10,
        newUnitCost: 80,
      );
      // (20*50 + 10*80) / 30 = (1000+800)/30 = 60
      expect(avg, 60);
    });
    test('zero total quantity returns 0', () {
      final avg = svc.calculateWeightedAverage(
        currentQuantity: 0,
        currentAvgCost: 100,
        newQuantity: 0,
        newUnitCost: 50,
      );
      expect(avg, 0);
    });
  });

  group('computeValuation', () {
    test('computes total value', () {
      final r = svc.computeValuation(
        productId: 'p1',
        productName: 'Widget',
        currentStock: 100,
        unitCost: 25,
      );
      expect(r.totalValue, 2500);
      expect(r.method, ValuationMethod.simpleAverage);
    });
    test('supports FIFO method', () {
      final r = svc.computeValuation(
        productId: 'p1',
        productName: 'W',
        currentStock: 50,
        unitCost: 30,
        method: ValuationMethod.fifo,
      );
      expect(r.method, ValuationMethod.fifo);
    });
  });
}
