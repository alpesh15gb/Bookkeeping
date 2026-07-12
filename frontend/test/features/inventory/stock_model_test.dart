// Tests for StockMovement, StockBalance, NegativeStockPolicy models.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';

void main() {
  group('StockMovement.direction', () {
    test('positive quantity is in', () {
      const m = StockMovement(
        id: 'm1',
        productId: 'p1',
        productName: 'P',
        quantity: 50,
        balanceQuantity: 50,
        referenceType: MovementReferenceType.bill,
      );
      expect(m.direction, MovementDirection.in_);
    });
    test('negative quantity is out', () {
      const m = StockMovement(
        id: 'm2',
        productId: 'p1',
        productName: 'P',
        quantity: -30,
        balanceQuantity: 20,
        referenceType: MovementReferenceType.invoice,
      );
      expect(m.direction, MovementDirection.out);
    });
    test('totalValue computed', () {
      const m = StockMovement(
        id: 'm3',
        productId: 'p1',
        productName: 'P',
        quantity: 10,
        balanceQuantity: 10,
        referenceType: MovementReferenceType.bill,
        rate: 25,
      );
      expect(m.totalValue, 250);
    });
  });

  group('StockMovement.fromJson', () {
    test('parses stock-in entry', () {
      final m = StockMovement.fromJson({
        'id': 'm1',
        'product_id': 'p1',
        'product_name': 'Widget',
        'quantity': '100.0000',
        'balance_quantity': '100.0000',
        'reference_type': 'BILL',
        'reference_id': 'bill-1',
        'rate': '15.5000',
        'created_at': '2025-07-01T10:00:00Z',
      });
      expect(m.quantity, 100.0);
      expect(m.referenceType, MovementReferenceType.bill);
      expect(m.rate, 15.5);
    });
    test('parses stock-out entry', () {
      final m = StockMovement.fromJson({
        'id': 'm2',
        'product_id': 'p1',
        'product_name': 'Widget',
        'quantity': '-50.0000',
        'balance_quantity': '50.0000',
        'reference_type': 'INVOICE',
      });
      expect(m.quantity, -50.0);
      expect(m.referenceType, MovementReferenceType.invoice);
    });
    test('defaults for unknown reference type', () {
      final m = StockMovement.fromJson({
        'id': 'm3',
        'product_id': 'p1',
        'product_name': 'P',
        'reference_type': 'UNKNOWN',
      });
      expect(m.referenceType, MovementReferenceType.adjustment);
    });
  });

  group('StockBalance', () {
    test('stockValue computed', () {
      final b = StockBalance(
        productId: 'p1',
        productName: 'P',
        currentStock: 50,
        unitCost: 20,
      );
      expect(b.stockValue, 1000);
    });
    test('isLowStock below reorder', () {
      final b = StockBalance(
        productId: 'p1',
        currentStock: 5,
        reorderLevel: 10,
      );
      expect(b.isLowStock, true);
    });
    test('isLowStock false when above reorder', () {
      final b = StockBalance(
        productId: 'p1',
        currentStock: 20,
        reorderLevel: 10,
      );
      expect(b.isLowStock, false);
    });
    test('isLowStock false when reorder is zero', () {
      final b = StockBalance(productId: 'p1', currentStock: 5, reorderLevel: 0);
      expect(b.isLowStock, false);
    });
    test('isOutOfStock when near zero', () {
      final b = StockBalance(productId: 'p1', currentStock: 0.001);
      expect(b.isOutOfStock, true);
    });
    test('fromProductJson', () {
      final b = StockBalance.fromProductJson({
        'id': 'p1',
        'name': 'Widget',
        'current_stock': 75,
        'unit_cost': 12.5,
        'reorder_level': 20,
      });
      expect(b.productId, 'p1');
      expect(b.currentStock, 75);
      expect(b.unitCost, 12.5);
      expect(b.reorderLevel, 20);
    });
  });

  group('MovementReferenceType', () {
    test('fromString matches backend values', () {
      expect(
        MovementReferenceType.fromString('INVOICE'),
        MovementReferenceType.invoice,
      );
      expect(
        MovementReferenceType.fromString('BILL'),
        MovementReferenceType.bill,
      );
      expect(
        MovementReferenceType.fromString('INVENTORY_ADJUSTMENT'),
        MovementReferenceType.adjustment,
      );
      expect(
        MovementReferenceType.fromString('TRANSFER'),
        MovementReferenceType.transfer,
      );
    });
    test('unknown defaults to adjustment', () {
      expect(
        MovementReferenceType.fromString('X'),
        MovementReferenceType.adjustment,
      );
    });
  });
}
