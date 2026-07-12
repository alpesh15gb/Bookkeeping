// Tests for Vendor Payments — allocation engine, validation.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/vendor_payments/models/outstanding_bill.dart';
import 'package:apexbooks/features/purchases/vendor_payments/models/vendor_payment.dart';
import 'package:apexbooks/features/purchases/vendor_payments/models/vendor_payment_enums.dart';
import 'package:apexbooks/features/purchases/vendor_payments/services/payable_allocation_service.dart';
import 'package:apexbooks/features/purchases/vendor_payments/services/vendor_payment_validation_service.dart';

void main() {
  const allocSvc = PayableAllocationService();
  const valSvc = VendorPaymentValidationService();

  group('OutstandingBill', () {
    test('outstanding computed', () {
      const b = OutstandingBill(id: 'b1', total: 1000, amountPaid: 400);
      expect(b.outstanding, 600);
    });
    test('isClosed when fully paid', () {
      const b = OutstandingBill(id: 'b1', total: 1000, amountPaid: 1000);
      expect(b.isClosed, true);
    });
  });

  group('suggestAllocations', () {
    test('allocates oldest due first', () {
      final bills = [
        OutstandingBill(
          id: 'b1',
          billNumber: 'BILL-1',
          total: 500,
          dueDate: '2025-07-01',
        ),
        OutstandingBill(
          id: 'b2',
          billNumber: 'BILL-2',
          total: 300,
          dueDate: '2025-06-01',
        ),
      ];
      final allocs = allocSvc.suggestAllocations(
        bills: bills,
        paymentAmount: 600,
      );
      expect(allocs.length, 2);
      expect(allocs[0].billId, 'b2'); // older due date first
      expect(allocs[0].amount, 300);
      expect(allocs[1].billId, 'b1');
      expect(allocs[1].amount, 300);
    });
    test('partial allocation when payment < total outstanding', () {
      final bills = [
        OutstandingBill(
          id: 'b1',
          billNumber: 'BILL-1',
          total: 1000,
          dueDate: '2025-07-01',
        ),
      ];
      final allocs = allocSvc.suggestAllocations(
        bills: bills,
        paymentAmount: 400,
      );
      expect(allocs.length, 1);
      expect(allocs[0].amount, 400);
    });
    test('skips closed bills', () {
      final bills = [
        OutstandingBill(
          id: 'b1',
          billNumber: 'BILL-1',
          total: 500,
          amountPaid: 500,
          dueDate: '2025-07-01',
        ),
        OutstandingBill(
          id: 'b2',
          billNumber: 'BILL-2',
          total: 300,
          dueDate: '2025-08-01',
        ),
      ];
      final allocs = allocSvc.suggestAllocations(
        bills: bills,
        paymentAmount: 300,
      );
      expect(allocs.length, 1);
      expect(allocs[0].billId, 'b2');
    });
  });

  group('validateAllocations', () {
    test('valid allocations pass', () {
      final bills = [OutstandingBill(id: 'b1', total: 1000, amountPaid: 0)];
      final allocs = [PaymentAllocation(billId: 'b1', amount: 500)];
      expect(
        allocSvc.validateAllocations(
          bills: bills,
          allocations: allocs,
          paymentAmount: 500,
        ),
        isNull,
      );
    });
    test('over-allocation rejected', () {
      final bills = [OutstandingBill(id: 'b1', total: 1000, amountPaid: 0)];
      final allocs = [PaymentAllocation(billId: 'b1', amount: 1200)];
      expect(
        allocSvc.validateAllocations(
          bills: bills,
          allocations: allocs,
          paymentAmount: 1200,
        ),
        contains('exceeds outstanding'),
      );
    });
    test('unknown bill rejected', () {
      final bills = [OutstandingBill(id: 'b1', total: 1000)];
      final allocs = [PaymentAllocation(billId: 'unknown', amount: 500)];
      expect(
        allocSvc.validateAllocations(
          bills: bills,
          allocations: allocs,
          paymentAmount: 500,
        ),
        contains('unknown'),
      );
    });
    test('empty allocations rejected', () {
      expect(
        allocSvc.validateAllocations(
          bills: [],
          allocations: [],
          paymentAmount: 500,
        ),
        contains('required'),
      );
    });
  });

  group('totalAllocated and unallocatedAmount', () {
    test('sums allocations', () {
      final allocs = [
        PaymentAllocation(billId: 'b1', amount: 300),
        PaymentAllocation(billId: 'b2', amount: 200),
      ];
      expect(allocSvc.totalAllocated(allocs), 500);
    });
    test('unallocated remainder', () {
      final allocs = [PaymentAllocation(billId: 'b1', amount: 300)];
      expect(
        allocSvc.unallocatedAmount(paymentAmount: 500, allocations: allocs),
        200,
      );
    });
  });

  group('validateForCreate', () {
    test('valid payment passes', () {
      const p = VendorPayment(
        id: 'p1',
        paymentNumber: 'PAY-001',
        contactId: 'c1',
        paymentDate: '2025-07-01',
        amount: 500,
        allocations: [PaymentAllocation(billId: 'b1', amount: 500)],
      );
      expect(valSvc.validateForCreate(p), isNull);
    });
    test('zero amount rejected', () {
      const p = VendorPayment(
        id: 'p1',
        paymentNumber: 'PAY-001',
        contactId: 'c1',
        paymentDate: '2025-07-01',
        amount: 0,
        allocations: [PaymentAllocation(billId: 'b1', amount: 0)],
      );
      expect(valSvc.validateForCreate(p), contains('greater than zero'));
    });
  });

  group('validateCancel', () {
    test('active can cancel', () {
      const p = VendorPayment(id: 'p1', status: VendorPaymentStatus.active);
      expect(valSvc.validateCancel(p), isNull);
    });
    test('already cancelled rejected', () {
      const p = VendorPayment(id: 'p1', status: VendorPaymentStatus.cancelled);
      expect(valSvc.validateCancel(p), contains('already'));
    });
  });
}
