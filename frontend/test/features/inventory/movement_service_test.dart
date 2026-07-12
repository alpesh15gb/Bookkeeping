// Tests for MovementService — balance reconciliation from movement history.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';

/// Static helper matching MovementService.calculateBalanceFromMovements.
double calculateBalanceFromMovements(List<StockMovement> movements) {
  double balance = 0;
  for (final m in movements) {
    balance += m.quantity;
  }
  return balance;
}

void main() {
  group('calculateBalanceFromMovements', () {
    test('sum of movements equals balance', () {
      final movements = [
        StockMovement(
          id: 'm1',
          productId: 'p1',
          productName: 'P',
          quantity: 100,
          balanceQuantity: 100,
          referenceType: MovementReferenceType.bill,
        ),
        StockMovement(
          id: 'm2',
          productId: 'p1',
          productName: 'P',
          quantity: -30,
          balanceQuantity: 70,
          referenceType: MovementReferenceType.invoice,
        ),
        StockMovement(
          id: 'm3',
          productId: 'p1',
          productName: 'P',
          quantity: 20,
          balanceQuantity: 90,
          referenceType: MovementReferenceType.bill,
        ),
      ];
      expect(calculateBalanceFromMovements(movements), 90.0);
    });
    test('empty list returns 0', () {
      expect(calculateBalanceFromMovements([]), 0);
    });
    test('negative opening balance', () {
      final movements = [
        StockMovement(
          id: 'm1',
          productId: 'p1',
          productName: 'P',
          quantity: -10,
          balanceQuantity: -10,
          referenceType: MovementReferenceType.adjustment,
        ),
        StockMovement(
          id: 'm2',
          productId: 'p1',
          productName: 'P',
          quantity: 50,
          balanceQuantity: 40,
          referenceType: MovementReferenceType.bill,
        ),
      ];
      expect(calculateBalanceFromMovements(movements), 40.0);
    });
  });
}
