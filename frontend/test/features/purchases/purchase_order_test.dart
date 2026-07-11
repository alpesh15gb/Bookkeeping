// Tests for PurchaseOrder state machine, validation, and calculation.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/purchase_orders/models/purchase_order_status.dart';
import 'package:apexbooks/features/purchases/purchase_orders/models/purchase_order_line.dart';
import 'package:apexbooks/features/purchases/purchase_orders/models/purchase_order.dart';
import 'package:apexbooks/features/purchases/purchase_orders/services/purchase_order_validation_service.dart';
import 'package:apexbooks/features/purchases/purchase_orders/services/purchase_order_calculation_service.dart';

void main() {
  const valSvc = PurchaseOrderValidationService();
  const calcSvc = PurchaseOrderCalculationService();

  group('PurchaseOrderStatus', () {
    test('isEditable only for draft', () {
      expect(PurchaseOrderStatus.draft.isEditable, true);
      expect(PurchaseOrderStatus.confirmed.isEditable, false);
    });
    test('isFinalized for confirmed and received', () {
      expect(PurchaseOrderStatus.confirmed.isFinalized, true);
      expect(PurchaseOrderStatus.received.isFinalized, true);
      expect(PurchaseOrderStatus.draft.isFinalized, false);
    });
    test('isCancellable for draft and confirmed', () {
      expect(PurchaseOrderStatus.draft.isCancellable, true);
      expect(PurchaseOrderStatus.confirmed.isCancellable, true);
      expect(PurchaseOrderStatus.received.isCancellable, false);
      expect(PurchaseOrderStatus.cancelled.isCancellable, false);
    });
    test('fromString parses backend values', () {
      expect(
        PurchaseOrderStatus.fromString('DRAFT'),
        PurchaseOrderStatus.draft,
      );
      expect(
        PurchaseOrderStatus.fromString('CONFIRMED'),
        PurchaseOrderStatus.confirmed,
      );
      expect(
        PurchaseOrderStatus.fromString('RECEIVED'),
        PurchaseOrderStatus.received,
      );
      expect(
        PurchaseOrderStatus.fromString('CANCELLED'),
        PurchaseOrderStatus.cancelled,
      );
      expect(PurchaseOrderStatus.fromString('X'), PurchaseOrderStatus.draft);
    });
  });

  group('validateTransition', () {
    test('Draft → Confirmed allowed', () {
      expect(
        valSvc.validateTransition(
          current: PurchaseOrderStatus.draft,
          target: PurchaseOrderStatus.confirmed,
        ),
        isNull,
      );
    });
    test('Draft → Cancelled allowed', () {
      expect(
        valSvc.validateTransition(
          current: PurchaseOrderStatus.draft,
          target: PurchaseOrderStatus.cancelled,
        ),
        isNull,
      );
    });
    test('Confirmed → Received allowed', () {
      expect(
        valSvc.validateTransition(
          current: PurchaseOrderStatus.confirmed,
          target: PurchaseOrderStatus.received,
        ),
        isNull,
      );
    });
    test('Confirmed → Cancelled allowed', () {
      expect(
        valSvc.validateTransition(
          current: PurchaseOrderStatus.confirmed,
          target: PurchaseOrderStatus.cancelled,
        ),
        isNull,
      );
    });
    test('Received → any rejected (terminal)', () {
      expect(
        valSvc.validateTransition(
          current: PurchaseOrderStatus.received,
          target: PurchaseOrderStatus.confirmed,
        ),
        isNotNull,
      );
    });
    test('Draft → Received rejected (must confirm first)', () {
      expect(
        valSvc.validateTransition(
          current: PurchaseOrderStatus.draft,
          target: PurchaseOrderStatus.received,
        ),
        isNotNull,
      );
    });
  });

  group('validateForSubmit', () {
    test('valid PO returns null', () {
      const po = PurchaseOrder(
        id: 'po1',
        poNumber: 'PO-001',
        contactId: 'c1',
        orderDate: '2025-07-01',
        dueDate: '2025-07-15',
        posStateCode: '27',
        lines: [
          PurchaseOrderLine(
            productId: 'p1',
            quantity: 10,
            rate: 100,
            hsnSac: '1234',
            gstRate: 18,
          ),
        ],
      );
      expect(valSvc.validateForSubmit(po), isNull);
    });
    test('missing PO number rejected', () {
      const po = PurchaseOrder(
        id: 'po1',
        contactId: 'c1',
        orderDate: '2025-07-01',
        dueDate: '2025-07-15',
        posStateCode: '27',
        lines: [
          PurchaseOrderLine(
            productId: 'p1',
            quantity: 10,
            rate: 100,
            hsnSac: '1234',
            gstRate: 18,
          ),
        ],
      );
      expect(valSvc.validateForSubmit(po), contains('PO number'));
    });
    test('empty lines rejected', () {
      const po = PurchaseOrder(
        id: 'po1',
        poNumber: 'PO-001',
        contactId: 'c1',
        orderDate: '2025-07-01',
        dueDate: '2025-07-15',
        posStateCode: '27',
      );
      expect(valSvc.validateForSubmit(po), contains('line item'));
    });
    test('invalid line quantity rejected', () {
      const po = PurchaseOrder(
        id: 'po1',
        poNumber: 'PO-001',
        contactId: 'c1',
        orderDate: '2025-07-01',
        dueDate: '2025-07-15',
        posStateCode: '27',
        lines: [
          PurchaseOrderLine(
            productId: 'p1',
            quantity: 0,
            rate: 100,
            hsnSac: '1234',
            gstRate: 18,
          ),
        ],
      );
      expect(valSvc.validateForSubmit(po), contains('Quantity'));
    });
  });

  group('calculateLine', () {
    test('computes subtotal, GST, and total', () {
      final line = calcSvc.calculateLine(
        line: const PurchaseOrderLine(
          productId: 'p1',
          quantity: 10,
          rate: 100,
          gstRate: 18,
        ),
      );
      expect(line.subtotal, 1000);
      expect(line.cgstAmount, 90);
      expect(line.total, 1180);
    });
    test('applies discount', () {
      final line = calcSvc.calculateLine(
        line: const PurchaseOrderLine(
          productId: 'p1',
          quantity: 10,
          rate: 100,
          discount: 10,
          gstRate: 18,
        ),
      );
      expect(line.subtotal, 1000);
      expect(line.total, 1062);
    });
  });

  group('PurchaseOrderLine receipt flags', () {
    test('partial receipt', () {
      const line = PurchaseOrderLine(quantity: 100, quantityReceived: 40);
      expect(line.outstandingQuantity, 60);
      expect(line.isPartiallyReceived, true);
    });
    test('fully received', () {
      const line = PurchaseOrderLine(quantity: 100, quantityReceived: 100);
      expect(line.isFullyReceived, true);
    });
  });

  group('PurchaseOrder.fromJson', () {
    test('parses full response', () {
      final po = PurchaseOrder.fromJson({
        'id': 'po1',
        'po_number': 'PO-001',
        'contact_id': 'c1',
        'contact': {'name': 'Acme Corp'},
        'order_date': '2025-07-01',
        'due_date': '2025-07-15',
        'status': 'CONFIRMED',
        'pos_state_code': '27',
        'subtotal': '1000.0000',
        'total': '1180.0000',
        'lines': [
          {
            'id': 'l1',
            'product_id': 'p1',
            'quantity': '10',
            'rate': '100',
            'hsn_sac': '1234',
            'gst_rate': '18',
            'subtotal': '1000',
            'cgst_amount': '90',
            'sgst_amount': '90',
            'total': '1180',
            'quantity_received': '5',
          },
        ],
      });
      expect(po.poNumber, 'PO-001');
      expect(po.contactName, 'Acme Corp');
      expect(po.lines[0].quantity, 10);
    });
  });
}
