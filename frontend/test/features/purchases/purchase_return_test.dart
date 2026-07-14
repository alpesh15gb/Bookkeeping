// Tests for Purchase Return models and lifecycle.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return_status.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return_line.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return.dart';

void main() {
  group('PurchaseReturnStatus', () {
    test('isEditable only for draft', () {
      expect(PurchaseReturnStatus.draft.isEditable, true);
      expect(PurchaseReturnStatus.posted.isEditable, false);
    });
    test('isCancellable for posted', () {
      expect(PurchaseReturnStatus.posted.isCancellable, true);
      expect(PurchaseReturnStatus.cancelled.isCancellable, false);
    });
    test('fromString', () {
      expect(
        PurchaseReturnStatus.fromString('POSTED'),
        PurchaseReturnStatus.posted,
      );
      expect(PurchaseReturnStatus.fromString('X'), PurchaseReturnStatus.draft);
    });
  });

  group('PurchaseReturnLine', () {
    test('toCreatePayload', () {
      const line = PurchaseReturnLine(
        billLineId: 'bl1',
        productId: 'p1',
        quantityReturned: 5,
        rate: 100,
        hsnSac: '84713010',
        gstRate: 18,
        reason: 'Damaged',
      );
      final p = line.toCreatePayload();
      expect(p['product_id'], 'p1');
      expect(p['quantity'], 5);
      expect(p['bill_line_id'], 'bl1');
      expect(p['description'], 'Damaged');
    });
    test('fromJson', () {
      final line = PurchaseReturnLine.fromJson({
        'id': 'l1',
        'product_id': 'p1',
        'product_name': 'Widget',
        'quantity': '10',
        'rate': '50',
        'gst_rate': '18',
        'subtotal': '500',
        'total': '590',
      });
      expect(line.productName, 'Widget');
      expect(line.quantityReturned, 10);
    });
  });

  group('PurchaseReturn', () {
    test('fromJson parses full response', () {
      final ret = PurchaseReturn.fromJson({
        'id': 'r1',
        'return_number': 'RET-001',
        'bill_id': 'b1',
        'bill_number': 'BILL-001',
        'contact': {'name': 'Acme'},
        'issue_date': '2025-07-20',
        'status': 'POSTED',
        'subtotal': '500',
        'cgst_amount': '45',
        'sgst_amount': '45',
        'total': '590',
        'lines': [
          {'id': 'l1', 'product_id': 'p1', 'quantity': '5', 'rate': '100'},
        ],
      });
      expect(ret.returnNumber, 'RET-001');
      expect(ret.billNumber, 'BILL-001');
      expect(ret.contactName, 'Acme');
      expect(ret.status, PurchaseReturnStatus.posted);
      expect(ret.lines.length, 1);
      expect(ret.lines[0].quantityReturned, 5);
    });
    test('toCreatePayload', () {
      const ret = PurchaseReturn(
        id: 'r1',
        billId: 'b1',
        contactId: 'v1',
        posStateCode: '27',
        returnDate: '2025-07-20',
        lines: [
          PurchaseReturnLine(
            billLineId: 'bl1',
            productId: 'p1',
            quantityReturned: 5,
            rate: 100,
            hsnSac: '84713010',
            gstRate: 18,
          ),
        ],
      );
      final p = ret.toCreatePayload();
      expect(p['bill_id'], 'b1');
      expect(p['issue_date'], '2025-07-20');
      expect(p['contact_id'], 'v1');
      expect((p['line_items'] as List).length, 1);
    });
  });

  group('PurchaseReturnListItem', () {
    test('fromJson', () {
      final item = PurchaseReturnListItem.fromJson({
        'id': 'r1',
        'return_number': 'RET-001',
        'issue_date': '2025-07-20',
        'status': 'DRAFT',
        'total': '590',
        'contact_name': 'Acme',
      });
      expect(item.returnNumber, 'RET-001');
      expect(item.status, PurchaseReturnStatus.draft);
    });
  });
}
