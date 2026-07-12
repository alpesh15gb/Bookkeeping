// Tests for InventoryAdjustment and AdjustmentLine models.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/inventory/adjustment/services/adjustment_service.dart';

void main() {
  group('AdjustmentLine', () {
    test('isIncrease for positive change', () {
      const line = AdjustmentLine(productId: 'p1', quantityChange: 10);
      expect(line.isIncrease, true);
    });
    test('not increase for negative change', () {
      const line = AdjustmentLine(productId: 'p1', quantityChange: -5);
      expect(line.isIncrease, false);
    });
    test('toCreatePayload', () {
      const line = AdjustmentLine(
        productId: 'p1',
        quantityChange: 10,
        unitCost: 50,
      );
      final p = line.toCreatePayload();
      expect(p['product_id'], 'p1');
      expect(p['quantity_change'], 10);
      expect(p['unit_cost'], 50);
    });
    test('fromJson', () {
      final line = AdjustmentLine.fromJson({
        'id': 'l1',
        'product_id': 'p1',
        'product_name': 'Widget',
        'quantity_change': 25,
        'unit_cost': 100.0,
        'total_cost': 2500.0,
      });
      expect(line.id, 'l1');
      expect(line.productName, 'Widget');
      expect(line.totalCost, 2500);
    });
  });

  group('InventoryAdjustment', () {
    test('isDraft and isConfirmed flags', () {
      const draft = InventoryAdjustment(id: 'a1', status: 'DRAFT');
      expect(draft.isDraft, true);
      expect(draft.isConfirmed, false);

      const confirmed = InventoryAdjustment(id: 'a2', status: 'CONFIRMED');
      expect(confirmed.isDraft, false);
      expect(confirmed.isConfirmed, true);
    });
    test('fromJson parses full response', () {
      final adj = InventoryAdjustment.fromJson({
        'id': 'a1',
        'adjustment_number': 'ADJ-001',
        'adjustment_date': '2025-07-15',
        'reason': 'Damaged stock',
        'status': 'CONFIRMED',
        'lines': [
          {
            'id': 'l1',
            'product_id': 'p1',
            'product_name': 'Widget',
            'quantity_change': -10,
            'unit_cost': 50,
            'total_cost': 500,
          },
        ],
        'created_at': '2025-07-15T10:00:00Z',
      });
      expect(adj.id, 'a1');
      expect(adj.adjustmentNumber, 'ADJ-001');
      expect(adj.isConfirmed, true);
      expect(adj.lines.length, 1);
      expect(adj.lines[0].productName, 'Widget');
    });
    test('fromJson defaults for empty lines', () {
      final adj = InventoryAdjustment.fromJson({'id': 'a1'});
      expect(adj.lines, isEmpty);
    });
  });

  group('AdjustmentListItem', () {
    test('fromJson parses list response', () {
      final item = AdjustmentListItem.fromJson({
        'id': 'a1',
        'adjustment_number': 'ADJ-001',
        'adjustment_date': '2025-07-15',
        'status': 'DRAFT',
        'created_at': '2025-07-15T10:00:00Z',
      });
      expect(item.id, 'a1');
      expect(item.status, 'DRAFT');
    });
  });
}
