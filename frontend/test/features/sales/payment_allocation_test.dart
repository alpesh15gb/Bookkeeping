// Tests for Payment Allocation logic — outstanding balance, partial payments,
// overpayment handling, and allocation ordering.
import 'package:flutter_test/flutter_test.dart';

/// Simulates the payment allocation logic that the backend enforces.
/// The frontend mirrors these rules in the payment form.
class PaymentAllocationLogic {
  /// Returns the amount that can still be allocated against an invoice.
  static double getOutstanding(double total, double amountPaid) =>
      (total - amountPaid).clamp(0, double.infinity);

  /// Checks if a proposed allocation is valid.
  static (bool valid, String? error) validateAllocation({
    required double invoiceTotal,
    required double alreadyPaid,
    required double allocationAmount,
  }) {
    if (allocationAmount <= 0) {
      return (false, 'Allocation must be greater than 0');
    }
    final outstanding = getOutstanding(invoiceTotal, alreadyPaid);
    if (allocationAmount > outstanding) {
      return (
        false,
        'Allocation (${allocationAmount.toStringAsFixed(2)}) exceeds outstanding (${outstanding.toStringAsFixed(2)})',
      );
    }
    return (true, null);
  }

  /// Given a payment amount and list of invoices with outstanding balances,
  /// returns the optimal allocation order (by due date, oldest first).
  static List<({String invoiceId, double allocate})> suggestAllocations({
    required double paymentAmount,
    required List<({String invoiceId, double outstanding, String dueDate})>
    invoices,
  }) {
    // Sort by due date ascending (oldest first)
    final sorted =
        List<({String invoiceId, double outstanding, String dueDate})>.from(
          invoices,
        )..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final result = <({String invoiceId, double allocate})>[];
    var remaining = paymentAmount;
    for (final inv in sorted) {
      if (remaining <= 0) break;
      final allocate = (remaining < inv.outstanding)
          ? remaining
          : inv.outstanding;
      if (allocate > 0) {
        result.add((invoiceId: inv.invoiceId, allocate: allocate));
        remaining -= allocate;
      }
    }
    return result;
  }
}

void main() {
  group('PaymentAllocationLogic.getOutstanding', () {
    test('full amount unpaid', () {
      expect(PaymentAllocationLogic.getOutstanding(1000, 0), 1000);
    });

    test('fully paid', () {
      expect(PaymentAllocationLogic.getOutstanding(1000, 1000), 0);
    });

    test('partially paid', () {
      expect(PaymentAllocationLogic.getOutstanding(1000, 300), 700);
    });

    test('overpaid clamps to zero', () {
      expect(PaymentAllocationLogic.getOutstanding(1000, 1200), 0);
    });

    test('zero invoice', () {
      expect(PaymentAllocationLogic.getOutstanding(0, 0), 0);
    });
  });

  group('PaymentAllocationLogic.validateAllocation', () {
    test('full payment on unpaid invoice', () {
      final r = PaymentAllocationLogic.validateAllocation(
        invoiceTotal: 1000,
        alreadyPaid: 0,
        allocationAmount: 1000,
      );
      expect(r.$1, true);
    });

    test('partial payment', () {
      final r = PaymentAllocationLogic.validateAllocation(
        invoiceTotal: 1000,
        alreadyPaid: 0,
        allocationAmount: 500,
      );
      expect(r.$1, true);
    });

    test('excess payment rejected', () {
      final r = PaymentAllocationLogic.validateAllocation(
        invoiceTotal: 1000,
        alreadyPaid: 500,
        allocationAmount: 600,
      );
      expect(r.$1, false);
      expect(r.$2, contains('exceeds outstanding'));
    });

    test('zero allocation rejected', () {
      final r = PaymentAllocationLogic.validateAllocation(
        invoiceTotal: 1000,
        alreadyPaid: 0,
        allocationAmount: 0,
      );
      expect(r.$1, false);
      expect(r.$2, contains('greater than 0'));
    });
  });

  group('PaymentAllocationLogic.suggestAllocations', () {
    test('full payment to oldest invoice', () {
      final r = PaymentAllocationLogic.suggestAllocations(
        paymentAmount: 500,
        invoices: [
          (invoiceId: 'i1', outstanding: 200, dueDate: '2025-01-01'),
          (invoiceId: 'i2', outstanding: 400, dueDate: '2025-02-01'),
        ],
      );
      expect(r.length, 2);
      expect(r[0].invoiceId, 'i1');
      expect(r[0].allocate, 200);
      expect(r[1].invoiceId, 'i2');
      expect(r[1].allocate, 300);
    });

    test('payment covers exactly one invoice', () {
      final r = PaymentAllocationLogic.suggestAllocations(
        paymentAmount: 300,
        invoices: [
          (invoiceId: 'i1', outstanding: 300, dueDate: '2025-01-01'),
          (invoiceId: 'i2', outstanding: 500, dueDate: '2025-02-01'),
        ],
      );
      expect(r.length, 1);
      expect(r[0].invoiceId, 'i1');
      expect(r[0].allocate, 300);
    });

    test('single invoice partial payment', () {
      final r = PaymentAllocationLogic.suggestAllocations(
        paymentAmount: 300,
        invoices: [(invoiceId: 'i1', outstanding: 1000, dueDate: '2025-01-01')],
      );
      expect(r.length, 1);
      expect(r[0].invoiceId, 'i1');
      expect(r[0].allocate, 300);
    });

    test('overpayment situation', () {
      final r = PaymentAllocationLogic.suggestAllocations(
        paymentAmount: 2000,
        invoices: [
          (invoiceId: 'i1', outstanding: 500, dueDate: '2025-01-01'),
          (invoiceId: 'i2', outstanding: 300, dueDate: '2025-02-01'),
        ],
      );
      expect(r.length, 2);
      expect(r[0].allocate, 500);
      expect(r[1].allocate, 300);
    });

    test('no invoices returns empty', () {
      final r = PaymentAllocationLogic.suggestAllocations(
        paymentAmount: 1000,
        invoices: [],
      );
      expect(r, isEmpty);
    });
  });
}
