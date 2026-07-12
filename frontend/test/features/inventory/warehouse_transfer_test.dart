// Tests for Warehouse and Transfer models.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/inventory/warehouse/services/warehouse_service.dart';
import 'package:apexbooks/features/inventory/transfers/services/transfer_service.dart';

void main() {
  group('Warehouse.fromJson', () {
    test('parses full response', () {
      final wh = Warehouse.fromJson({
        'id': 'wh-1',
        'name': 'Main Warehouse',
        'code': 'MAIN',
        'location': 'Building A',
        'is_active': true,
      });
      expect(wh.id, 'wh-1');
      expect(wh.name, 'Main Warehouse');
      expect(wh.code, 'MAIN');
      expect(wh.location, 'Building A');
      expect(wh.isActive, true);
    });
    test('defaults on minimal JSON', () {
      final wh = Warehouse.fromJson({'id': 'wh-1'});
      expect(wh.isActive, true);
      expect(wh.name, '');
    });
  });

  group('Transfer', () {
    test('state flags', () {
      const draft = Transfer(
        id: 't1',
        fromWarehouseId: 'wh-1',
        toWarehouseId: 'wh-2',
        status: 'DRAFT',
      );
      expect(draft.isDraft, true);
      expect(draft.isCompleted, false);

      const done = Transfer(
        id: 't2',
        fromWarehouseId: 'wh-1',
        toWarehouseId: 'wh-2',
        status: 'COMPLETED',
      );
      expect(done.isCompleted, true);
    });
    test('fromJson parses response', () {
      final t = Transfer.fromJson({
        'id': 't1',
        'transfer_number': 'TRF-001',
        'transfer_date': '2025-07-20',
        'from_warehouse_id': 'wh-1',
        'from_warehouse_name': 'Main',
        'to_warehouse_id': 'wh-2',
        'to_warehouse_name': 'Store',
        'status': 'DRAFT',
        'lines': [
          {
            'product_id': 'p1',
            'product_name': 'Widget',
            'quantity': 10,
            'rate': 25,
          },
        ],
        'created_at': '2025-07-20T08:00:00Z',
      });
      expect(t.transferNumber, 'TRF-001');
      expect(t.fromWarehouseName, 'Main');
      expect(t.toWarehouseName, 'Store');
      expect(t.lines.length, 1);
      expect(t.lines[0].quantity, 10);
    });
    test('fromJson empty lines default', () {
      final t = Transfer.fromJson({
        'id': 't1',
        'from_warehouse_id': 'wh-1',
        'to_warehouse_id': 'wh-2',
      });
      expect(t.lines, isEmpty);
    });
    test('TransferLine.fromJson', () {
      final line = TransferLine.fromJson({
        'product_id': 'p1',
        'product_name': 'Widget',
        'quantity': 15,
        'rate': 30,
      });
      expect(line.productName, 'Widget');
      expect(line.quantity, 15);
    });
  });
}
