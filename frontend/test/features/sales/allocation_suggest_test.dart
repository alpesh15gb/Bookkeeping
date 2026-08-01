// Tests for AllocationService.suggestAllocations — oldest-due-first engine.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/payments/services/allocation_service.dart';
import 'package:apexbooks/features/sales/payments/models/outstanding_invoice.dart';

void main() {
  const alloc = AllocationService();
  const eps = 0.001;

  final invoices = [
    const OutstandingInvoice(
      id: 'i1',
      invoiceNumber: 'INV-001',
      total: 1000,
      amountPaid: 0,
      dueDate: '2025-03-01',
      contactName: 'A',
    ),
    const OutstandingInvoice(
      id: 'i2',
      invoiceNumber: 'INV-002',
      total: 500,
      amountPaid: 0,
      dueDate: '2025-01-15',
      contactName: 'A',
    ), // oldest
    const OutstandingInvoice(
      id: 'i3',
      invoiceNumber: 'INV-003',
      total: 2000,
      amountPaid: 0,
      dueDate: '2025-06-01',
      contactName: 'A',
    ),
  ];

  group('suggestAllocations', () {
    test('oldest due first (i2 before i1 before i3)', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 2000,
        invoices: invoices,
      );
      expect(r.allocations.length, 3);
      expect(r.allocations[0].invoiceId, 'i2');
      expect(r.allocations[0].amount, closeTo(500, eps));
      expect(r.allocations[1].invoiceId, 'i1');
      expect(r.allocations[1].amount, closeTo(1000, eps));
      expect(r.allocations[2].invoiceId, 'i3');
      expect(r.allocations[2].amount, closeTo(500, eps));
      expect(r.surplus, closeTo(0, eps));
    });

    test('exact cover oldest invoice', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 500,
        invoices: invoices,
      );
      expect(r.allocations.length, 1);
      expect(r.allocations[0].invoiceId, 'i2');
      expect(r.allocations[0].amount, closeTo(500, eps));
      expect(r.surplus, closeTo(0, eps));
    });

    test('partial payment on oldest', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 300,
        invoices: invoices,
      );
      expect(r.allocations.length, 1);
      expect(r.allocations[0].invoiceId, 'i2');
      expect(r.allocations[0].amount, closeTo(300, eps));
      expect(r.surplus, closeTo(0, eps));
    });

    test('payment exceeds all outstanding (surplus)', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 5000,
        invoices: invoices,
      );
      expect(r.allocations.length, 3);
      expect(r.surplus, closeTo(1500, eps)); // excess credit
    });

    test('zero payment empty', () {
      final r = alloc.suggestAllocations(paymentAmount: 0, invoices: invoices);
      expect(r.allocations, isEmpty);
    });

    test('no invoices empty', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 1000,
        invoices: const [],
      );
      expect(r.allocations, isEmpty);
      expect(r.surplus, closeTo(1000, eps));
    });

    test('already-paid invoices skipped', () {
      final paid = [
        const OutstandingInvoice(
          id: 'i1',
          invoiceNumber: 'INV-001',
          total: 1000,
          amountPaid: 1000,
          dueDate: '2025-01-01',
          contactName: 'A',
        ),
        const OutstandingInvoice(
          id: 'i2',
          invoiceNumber: 'INV-002',
          total: 500,
          amountPaid: 0,
          dueDate: '2025-02-01',
          contactName: 'A',
        ),
      ];
      final r = alloc.suggestAllocations(paymentAmount: 500, invoices: paid);
      expect(r.allocations.length, 1);
      expect(r.allocations[0].invoiceId, 'i2');
      expect(r.allocations[0].amount, closeTo(500, eps));
    });

    test('partially paid invoice correct outstanding', () {
      final partial = [
        const OutstandingInvoice(
          id: 'i1',
          invoiceNumber: 'INV-001',
          total: 1000,
          amountPaid: 400,
          dueDate: '2025-01-01',
          contactName: 'A',
        ),
      ];
      final r = alloc.suggestAllocations(
        paymentAmount: 1000,
        invoices: partial,
      );
      expect(r.allocations.length, 1);
      expect(r.allocations[0].amount, closeTo(600, eps)); // 1000-400
      expect(r.surplus, closeTo(400, eps));
    });
  });
}
