// Tests for AllocationService — core validation functions.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/payments/services/allocation_service.dart';
import 'package:apexbooks/features/sales/payments/models/payment_models.dart';

void main() {
  const alloc = AllocationService();

  group('getOutstanding', () {
    test('full unpaid', () => expect(alloc.getOutstanding(1000, 0), 1000));
    test('fully paid', () => expect(alloc.getOutstanding(1000, 1000), 0));
    test('partial', () => expect(alloc.getOutstanding(1000, 300), 700));
    test('overpaid clamped', () => expect(alloc.getOutstanding(1000, 1200), 0));
  });

  group('validateAllocationAmount', () {
    test('full on unpaid', () {
      expect(
        alloc
            .validateAllocationAmount(
              invoiceTotal: 1000,
              alreadyPaid: 0,
              allocationAmount: 1000,
            )
            .$1,
        true,
      );
    });
    test('partial', () {
      expect(
        alloc
            .validateAllocationAmount(
              invoiceTotal: 1000,
              alreadyPaid: 0,
              allocationAmount: 500,
            )
            .$1,
        true,
      );
    });
    test('exceeds rejected', () {
      final r = alloc.validateAllocationAmount(
        invoiceTotal: 1000,
        alreadyPaid: 800,
        allocationAmount: 300,
      );
      expect(r.$1, false);
      expect(r.$2, contains('exceeds'));
    });
    test('zero rejected', () {
      expect(
        alloc
            .validateAllocationAmount(
              invoiceTotal: 1000,
              alreadyPaid: 0,
              allocationAmount: 0,
            )
            .$1,
        false,
      );
    });
    test('negative rejected', () {
      expect(
        alloc
            .validateAllocationAmount(
              invoiceTotal: 1000,
              alreadyPaid: 0,
              allocationAmount: -50,
            )
            .$1,
        false,
      );
    });
  });

  group('validateAllocationsSum', () {
    test('exact match', () {
      expect(
        alloc
            .validateAllocationsSum(
              paymentAmount: 1000,
              allocations: const [
                PaymentAllocation(invoiceId: 'i1', amount: 600),
                PaymentAllocation(invoiceId: 'i2', amount: 400),
              ],
            )
            .$1,
        true,
      );
    });
    test('less than payment (surplus)', () {
      expect(
        alloc
            .validateAllocationsSum(
              paymentAmount: 1000,
              allocations: const [
                PaymentAllocation(invoiceId: 'i1', amount: 500),
              ],
            )
            .$1,
        true,
      );
    });
    test('exceeds rejected', () {
      expect(
        alloc
            .validateAllocationsSum(
              paymentAmount: 500,
              allocations: const [
                PaymentAllocation(invoiceId: 'i1', amount: 600),
              ],
            )
            .$1,
        false,
      );
    });
    test('empty rejected', () {
      expect(
        alloc
            .validateAllocationsSum(paymentAmount: 500, allocations: const [])
            .$1,
        false,
      );
    });
  });

  group('preventDuplicateInvoice', () {
    test('duplicate detected', () {
      expect(
        alloc
            .preventDuplicateInvoice(
              allocations: const [
                PaymentAllocation(invoiceId: 'i1', amount: 100),
              ],
              invoiceId: 'i1',
            )
            .$1,
        false,
      );
    });
    test('new allowed', () {
      expect(
        alloc
            .preventDuplicateInvoice(
              allocations: const [
                PaymentAllocation(invoiceId: 'i1', amount: 100),
              ],
              invoiceId: 'i2',
            )
            .$1,
        true,
      );
    });
  });
}
