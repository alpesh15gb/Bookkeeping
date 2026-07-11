// Tests for Goods Receipt — lifecycle, over-receipt prevention.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/goods_receipts/models/goods_receipt_status.dart';
import 'package:apexbooks/features/purchases/goods_receipts/models/goods_receipt_line.dart';
import 'package:apexbooks/features/purchases/goods_receipts/models/goods_receipt.dart';
import 'package:apexbooks/features/purchases/goods_receipts/services/goods_receipt_validation_service.dart';

void main() {
  const valSvc = GoodsReceiptValidationService();

  group('GoodsReceiptStatus', () {
    test('isEditable only for draft', () {
      expect(GoodsReceiptStatus.draft.isEditable, true);
      expect(GoodsReceiptStatus.confirmed.isEditable, false);
    });
    test('isCancellable for confirmed', () {
      expect(GoodsReceiptStatus.confirmed.isCancellable, true);
      expect(GoodsReceiptStatus.cancelled.isCancellable, false);
    });
  });

  group('GoodsReceiptLine', () {
    test('partial receipt flags', () {
      const line = GoodsReceiptLine(quantityOrdered: 100, quantityReceived: 40);
      expect(line.outstandingQuantity, 60);
      expect(line.isPartial, true);
      expect(line.isComplete, false);
    });
    test('complete receipt', () {
      const line = GoodsReceiptLine(
        quantityOrdered: 100,
        quantityReceived: 100,
      );
      expect(line.isComplete, true);
    });
    test('over receipt detected', () {
      const line = GoodsReceiptLine(
        quantityOrdered: 100,
        quantityReceived: 110,
      );
      expect(line.isOverReceipt, true);
    });
  });

  group('validateLine — over-receipt prevention', () {
    test('within ordered allowed', () {
      const line = GoodsReceiptLine(
        productId: 'p1',
        quantityOrdered: 100,
        quantityReceived: 80,
      );
      expect(valSvc.validateLine(line), isNull);
    });
    test('exact ordered allowed', () {
      const line = GoodsReceiptLine(
        productId: 'p1',
        quantityOrdered: 100,
        quantityReceived: 100,
      );
      expect(valSvc.validateLine(line), isNull);
    });
    test('over-receipt rejected', () {
      const line = GoodsReceiptLine(
        productId: 'p1',
        quantityOrdered: 100,
        quantityReceived: 120,
      );
      expect(valSvc.validateLine(line), contains('Over-receipt'));
    });
    test('zero received rejected', () {
      const line = GoodsReceiptLine(
        productId: 'p1',
        quantityOrdered: 100,
        quantityReceived: 0,
      );
      expect(valSvc.validateLine(line), contains('greater than zero'));
    });
    test('missing product rejected', () {
      const line = GoodsReceiptLine(quantityOrdered: 100, quantityReceived: 50);
      expect(valSvc.validateLine(line), contains('Product'));
    });
  });

  group('validateForConfirm', () {
    test('valid receipt passes', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        purchaseOrderId: 'po1',
        receiptDate: '2025-07-10',
        lines: [
          GoodsReceiptLine(
            productId: 'p1',
            quantityOrdered: 100,
            quantityReceived: 50,
          ),
        ],
      );
      expect(valSvc.validateForConfirm(gr), isNull);
    });
    test('missing PO rejected', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        receiptDate: '2025-07-10',
        lines: [
          GoodsReceiptLine(
            productId: 'p1',
            quantityOrdered: 10,
            quantityReceived: 5,
          ),
        ],
      );
      expect(valSvc.validateForConfirm(gr), contains('Purchase order'));
    });
    test('empty lines rejected', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        purchaseOrderId: 'po1',
        receiptDate: '2025-07-10',
      );
      expect(valSvc.validateForConfirm(gr), contains('line'));
    });
  });

  group('validateHasReceivedQuantity', () {
    test('zero total rejected', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        purchaseOrderId: 'po1',
        receiptDate: '2025-07-10',
        lines: [
          GoodsReceiptLine(
            productId: 'p1',
            quantityOrdered: 100,
            quantityReceived: 0,
          ),
        ],
      );
      expect(valSvc.validateHasReceivedQuantity(gr), contains('zero'));
    });
    test('positive total passes', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        purchaseOrderId: 'po1',
        receiptDate: '2025-07-10',
        lines: [
          GoodsReceiptLine(
            productId: 'p1',
            quantityOrdered: 100,
            quantityReceived: 50,
          ),
        ],
      );
      expect(valSvc.validateHasReceivedQuantity(gr), isNull);
    });
  });

  group('GoodsReceipt aggregate', () {
    test('isComplete when all lines complete', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        purchaseOrderId: 'po1',
        receiptDate: '2025-07-10',
        lines: [
          GoodsReceiptLine(
            productId: 'p1',
            quantityOrdered: 100,
            quantityReceived: 100,
          ),
          GoodsReceiptLine(
            productId: 'p2',
            quantityOrdered: 50,
            quantityReceived: 50,
          ),
        ],
      );
      expect(gr.isComplete, true);
      expect(gr.totalReceived, 150);
    });
    test('isPartial when some received', () {
      const gr = GoodsReceipt(
        id: 'gr1',
        purchaseOrderId: 'po1',
        receiptDate: '2025-07-10',
        lines: [
          GoodsReceiptLine(
            productId: 'p1',
            quantityOrdered: 100,
            quantityReceived: 100,
          ),
          GoodsReceiptLine(
            productId: 'p2',
            quantityOrdered: 50,
            quantityReceived: 20,
          ),
        ],
      );
      expect(gr.isPartial, true);
      expect(gr.isComplete, false);
    });
  });

  group('GoodsReceipt.fromJson', () {
    test('parses full response', () {
      final gr = GoodsReceipt.fromJson({
        'id': 'gr1',
        'receipt_number': 'GR-001',
        'purchase_order_id': 'po1',
        'po_number': 'PO-001',
        'contact': {'name': 'Acme'},
        'receipt_date': '2025-07-10',
        'status': 'CONFIRMED',
        'lines': [
          {
            'id': 'l1',
            'product_id': 'p1',
            'quantity_ordered': '100',
            'quantity_received': '50',
          },
        ],
      });
      expect(gr.receiptNumber, 'GR-001');
      expect(gr.status, GoodsReceiptStatus.confirmed);
      expect(gr.lines[0].quantityReceived, 50);
    });
  });
}
