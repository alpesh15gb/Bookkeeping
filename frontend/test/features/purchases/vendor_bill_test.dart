// Tests for Vendor Bill — calculation, validation, state machine.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/vendor_bills/models/bill_status.dart';
import 'package:apexbooks/features/purchases/vendor_bills/models/bill_line.dart';
import 'package:apexbooks/features/purchases/vendor_bills/models/vendor_bill.dart';
import 'package:apexbooks/features/purchases/vendor_bills/services/bill_calculation_service.dart';
import 'package:apexbooks/features/purchases/vendor_bills/services/bill_validation_service.dart';

void main() {
  const calcSvc = BillCalculationService();
  const valSvc = BillValidationService();

  group('BillStatus', () {
    test('isEditable only for draft', () {
      expect(BillStatus.draft.isEditable, true);
      expect(BillStatus.posted.isEditable, false);
    });
    test('hasOutstanding for unpaid and partially paid', () {
      expect(BillStatus.unpaid.hasOutstanding, true);
      expect(BillStatus.partiallyPaid.hasOutstanding, true);
      expect(BillStatus.paid.hasOutstanding, false);
    });
    test('fromString', () {
      expect(BillStatus.fromString('PARTIALLY_PAID'), BillStatus.partiallyPaid);
      expect(BillStatus.fromString('X'), BillStatus.draft);
    });
  });

  group('calculateLine', () {
    test('computes totals', () {
      final line = calcSvc.calculateLine(
        line: BillLine(productId: 'p1', quantity: 10, rate: 100, gstRate: 18),
      );
      expect(line.subtotal, 1000);
      expect(line.cgstAmount, 90);
      expect(line.sgstAmount, 90);
      expect(line.total, 1180);
    });
  });

  group('calculateAll', () {
    test('aggregates', () {
      final r = calcSvc.calculateAll(
        lines: [
          BillLine(productId: 'p1', quantity: 10, rate: 100, gstRate: 18),
          BillLine(productId: 'p2', quantity: 5, rate: 200, gstRate: 18),
        ],
      );
      expect(r.subtotal, 2000);
      expect(r.total, 2360);
    });
  });

  group('calculateTds', () {
    test('TDS amount', () {
      expect(calcSvc.calculateTds(total: 10000, tdsRate: 10), 1000);
    });
    test('zero rate', () {
      expect(calcSvc.calculateTds(total: 10000, tdsRate: 0), 0);
    });
  });

  group('calculateRoundOff', () {
    test('negative round-off for .40', () {
      expect(
        calcSvc.calculateRoundOff(rawTotal: 1180.40),
        closeTo(-0.40, 0.01),
      );
    });
    test('positive round-off for .60', () {
      expect(calcSvc.calculateRoundOff(rawTotal: 1180.60), closeTo(0.40, 0.01));
    });
  });

  group('validateForPost', () {
    test('valid bill passes', () {
      const bill = VendorBill(
        id: 'b1',
        billNumber: 'BILL-001',
        contactId: 'c1',
        issueDate: '2025-07-01',
        dueDate: '2025-07-15',
        posStateCode: '27',
        lines: [
          BillLine(
            productId: 'p1',
            quantity: 10,
            rate: 100,
            hsnSac: '1234',
            gstRate: 18,
          ),
        ],
      );
      expect(valSvc.validateForPost(bill), isNull);
    });
    test('due date before issue date rejected', () {
      const bill = VendorBill(
        id: 'b1',
        billNumber: 'BILL-001',
        contactId: 'c1',
        issueDate: '2025-07-15',
        dueDate: '2025-07-01',
        posStateCode: '27',
        lines: [
          BillLine(
            productId: 'p1',
            quantity: 10,
            rate: 100,
            hsnSac: '1234',
            gstRate: 18,
          ),
        ],
      );
      expect(valSvc.validateForPost(bill), contains('Due date'));
    });
    test('invalid TDS rate rejected', () {
      const bill = VendorBill(
        id: 'b1',
        billNumber: 'BILL-001',
        contactId: 'c1',
        issueDate: '2025-07-01',
        dueDate: '2025-07-15',
        posStateCode: '27',
        tdsRate: 150,
        lines: [
          BillLine(
            productId: 'p1',
            quantity: 10,
            rate: 100,
            hsnSac: '1234',
            gstRate: 18,
          ),
        ],
      );
      expect(valSvc.validateForPost(bill), contains('TDS'));
    });
  });

  group('validateTransition', () {
    test('Draft → Posted allowed', () {
      expect(
        valSvc.validateTransition(
          current: BillStatus.draft,
          target: BillStatus.posted,
        ),
        isNull,
      );
    });
    test('Posted → Cancelled allowed', () {
      expect(
        valSvc.validateTransition(
          current: BillStatus.posted,
          target: BillStatus.cancelled,
        ),
        isNull,
      );
    });
    test('Paid is terminal', () {
      expect(
        valSvc.validateTransition(
          current: BillStatus.paid,
          target: BillStatus.cancelled,
        ),
        isNotNull,
      );
    });
  });

  group('validateTotalBalance', () {
    test('balanced bill passes', () {
      const bill = VendorBill(
        id: 'b1',
        subtotal: 1000,
        cgstAmount: 90,
        sgstAmount: 90,
        total: 1180,
      );
      expect(valSvc.validateTotalBalance(bill), isNull);
    });
    test('unbalanced bill rejected', () {
      const bill = VendorBill(
        id: 'b1',
        subtotal: 1000,
        cgstAmount: 90,
        sgstAmount: 90,
        total: 999,
      );
      expect(valSvc.validateTotalBalance(bill), contains('balance'));
    });
  });

  group('VendorBill outstanding', () {
    test('outstanding with TDS', () {
      const bill = VendorBill(
        id: 'b1',
        total: 1000,
        amountPaid: 600,
        tdsAmount: 100,
      );
      expect(bill.outstanding, 300);
    });
    test('isPaid when fully settled', () {
      const bill = VendorBill(
        id: 'b1',
        total: 1000,
        amountPaid: 900,
        tdsAmount: 100,
      );
      expect(bill.isPaid, true);
    });
  });
}
