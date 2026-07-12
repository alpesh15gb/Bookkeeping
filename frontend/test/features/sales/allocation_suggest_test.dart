// Tests for AllocationService.suggestAllocations — oldest-due-first engine.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/payments/services/allocation_service.dart';
import 'package:apexbooks/features/sales/payments/models/outstanding_invoice.dart';

void main() {
  const alloc = AllocationService();
  const _eps = 0.001;

  final invoices = [
    OutstandingInvoice(
      id: 'i1',
      invoiceNumber: 'INV-001',
      total: 1000,
      amountPaid: 0,
      dueDate: '2025-03-01',
      contactName: 'A',
    ),
    OutstandingInvoice(
      id: 'i2',
      invoiceNumber: 'INV-002',
      total: 500,
      amountPaid: 0,
      dueDate: '2025-01-15',
      contactName: 'A',
    ), // oldest
    OutstandingInvoice(
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
      expect(r.allocations[0].amount, closeTo(500, _eps));
      expect(r.allocations[1].invoiceId, 'i1');
      expect(r.allocations[1].amount, closeTo(1000, _eps));
      expect(r.allocations[2].invoiceId, 'i3');
      expect(r.allocations[2].amount, closeTo(500, _eps));
      expect(r.surplus, closeTo(0, _eps));
    });

    test('exact cover oldest invoice', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 500,
        invoices: invoices,
      );
      expect(r.allocations.length, 1);
      expect(r.allocations[0].invoiceId, 'i2');
      expect(r.allocations[0].amount, closeTo(500, _eps));
      expect(r.surplus, closeTo(0, _eps));
    });

    test('partial payment on oldest', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 300,
        invoices: invoices,
      );
      expect(r.allocations.length, 1);
      expect(r.allocations[0].invoiceId, 'i2');
      expect(r.allocations[0].amount, closeTo(300, _eps));
      expect(r.surplus, closeTo(0, _eps));
    });

    test('payment exceeds all outstanding (surplus)', () {
      final r = alloc.suggestAllocations(
        paymentAmount: 5000,
        invoices: invoices,
      );
      expect(r.allocations.length, 3);
      expect(r.surplus, closeTo(1500, _eps)); // excess credit
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
      expect(r.surplus, closeTo(1000, _eps));
    });

    test('already-paid invoices skipped', () {
      final paid = [
        OutstandingInvoice(
          id: 'i1',
          invoiceNumber: 'INV-001',
          total: 1000,
          amountPaid: 1000,
          dueDate: '2025-01-01',
          contactName: 'A',
        ),
        OutstandingInvoice(
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
      expect(r.allocations[0].amount, closeTo(500, _eps));
    });

    test('partially paid invoice correct outstanding', () {
      final partial = [
        OutstandingInvoice(
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
      expect(r.allocations[0].amount, closeTo(600, _eps)); // 1000-400
      expect(r.surplus, closeTo(400, _eps));
    });
  });
}
