// Tests for Payment, PaymentAllocation, PaymentListItem, OutstandingInvoice models.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/payments/models/payment_models.dart';
import 'package:apexbooks/features/sales/payments/models/payment_enums.dart';
import 'package:apexbooks/features/sales/payments/models/outstanding_invoice.dart';

void main() {
  group('PaymentAllocation', () {
    test('fromResponse parses full', () {
      final a = PaymentAllocation.fromResponse({
        'id': 'alloc-1',
        'invoice_id': 'inv-1',
        'amount': 500.0,
      });
      expect(a.id, 'alloc-1');
      expect(a.invoiceId, 'inv-1');
      expect(a.amount, 500.0);
    });

    test('toCreatePayload', () {
      final a = const PaymentAllocation(invoiceId: 'inv-1', amount: 500);
      final p = a.toCreatePayload();
      expect(p['invoice_id'], 'inv-1');
      expect(p['amount'], 500);
      expect(p.containsKey('id'), false);
    });

    test('copyWith', () {
      const a = PaymentAllocation(invoiceId: 'inv-1', amount: 100);
      expect(a.copyWith(amount: 200).amount, 200);
      expect(a.copyWith(invoiceId: 'inv-2').invoiceId, 'inv-2');
    });
  });

  group('Payment.fromJson', () {
    test('parses full response', () {
      final json = {
        'id': 'pay-1',
        'tenant_id': 't-1',
        'contact_id': 'c-1',
        'payment_number': 'RCPT-001',
        'payment_date': '2025-07-15',
        'payment_mode': 'BANK',
        'amount': 5000.0,
        'reference_number': 'CHQ-123',
        'description': 'Payment for INV-001',
        'status': 'ACTIVE',
        'contact_name': 'Acme Corp',
        'allocations': [
          {'id': 'a-1', 'invoice_id': 'inv-1', 'amount': 3000.0},
          {'id': 'a-2', 'invoice_id': 'inv-2', 'amount': 2000.0},
        ],
        'created_at': '2025-07-15T10:00:00Z',
        'updated_at': '2025-07-15T10:00:00Z',
      };
      final p = Payment.fromJson(json);
      expect(p.id, 'pay-1');
      expect(p.paymentNumber, 'RCPT-001');
      expect(p.paymentMode, PaymentMode.bank);
      expect(p.amount, 5000.0);
      expect(p.status, PaymentStatus.active);
      expect(p.contactName, 'Acme Corp');
      expect(p.allocations.length, 2);
      expect(p.allocations[0].amount, 3000.0);
      expect(p.allocatedTotal, 5000.0);
      expect(p.unallocated, 0);
    });

    test('defaults on minimal response', () {
      final json = {
        'id': 'pay-1',
        'payment_number': 'RCPT-001',
        'payment_date': '2025-07-15',
        'payment_mode': 'CASH',
        'amount': 1000,
        'status': 'ACTIVE',
        'contact_name': 'Test',
        'allocations': [],
      };
      final p = Payment.fromJson(json);
      expect(p.id, 'pay-1');
      expect(p.paymentMode, PaymentMode.cash);
      expect(p.allocations, isEmpty);
      expect(p.allocatedTotal, 0);
    });
  });

  group('PaymentListItem.fromJson', () {
    test('parses list response', () {
      final item = PaymentListItem.fromJson({
        'id': 'pay-2',
        'payment_number': 'RCPT-002',
        'payment_date': '2025-07-20',
        'payment_mode': 'UPI',
        'amount': 2500.0,
        'contact_name': 'Beta Ltd',
        'status': 'ACTIVE',
        'created_at': '2025-07-20T08:00:00Z',
      });
      expect(item.id, 'pay-2');
      expect(item.paymentNumber, 'RCPT-002');
      expect(item.paymentMode, PaymentMode.upi);
      expect(item.amount, 2500.0);
      expect(item.contactName, 'Beta Ltd');
      expect(item.status, PaymentStatus.active);
    });
  });

  group('OutstandingInvoice', () {
    test('computes outstanding correctly', () {
      final inv = OutstandingInvoice(id: 'inv-1', total: 1000, amountPaid: 300);
      expect(inv.outstanding, 700);
    });

    test('overpaid clamps to zero', () {
      final inv = OutstandingInvoice(
        id: 'inv-1',
        total: 1000,
        amountPaid: 1200,
      );
      expect(inv.outstanding, 0);
      expect(inv.isClosed, true);
    });

    test('isOverdue for past due date', () {
      final inv = OutstandingInvoice(
        id: 'inv-1',
        total: 1000,
        amountPaid: 0,
        dueDate: '2020-01-01',
      );
      expect(inv.isOverdue, true);
      expect(inv.daysOverdue, greaterThan(0));
    });

    test('not overdue for future date', () {
      final inv = OutstandingInvoice(
        id: 'inv-1',
        total: 1000,
        amountPaid: 0,
        dueDate: '2099-12-31',
      );
      expect(inv.isOverdue, false);
    });

    test('isClosed when fully paid', () {
      final inv = OutstandingInvoice(
        id: 'inv-1',
        total: 1000,
        amountPaid: 1000,
      );
      expect(inv.isClosed, true);
      expect(inv.isOverdue, false);
    });

    test('fromInvoiceJson parses', () {
      final inv = OutstandingInvoice.fromInvoiceJson({
        'id': 'inv-1',
        'invoice_number': 'INV-001',
        'total': 5000,
        'amount_paid': 2000,
        'due_date': '2025-08-01',
        'contact_name': 'Acme',
        'status': 'PARTIALLY_PAID',
      });
      expect(inv.id, 'inv-1');
      expect(inv.invoiceNumber, 'INV-001');
      expect(inv.total, 5000);
      expect(inv.outstanding, 3000);
    });
  });

  group('PaymentEnums', () {
    test('PaymentMode.fromString', () {
      expect(PaymentMode.fromString('CASH'), PaymentMode.cash);
      expect(PaymentMode.fromString('BANK'), PaymentMode.bank);
      expect(PaymentMode.fromString('UPI'), PaymentMode.upi);
      expect(PaymentMode.fromString('POS'), PaymentMode.pos);
      expect(PaymentMode.fromString('OTHER'), PaymentMode.other);
      expect(PaymentMode.fromString('INVALID'), PaymentMode.other);
    });

    test('PaymentStatus lifecycle', () {
      expect(PaymentStatus.active.isActive, true);
      expect(PaymentStatus.active.isCancellable, true);
      expect(PaymentStatus.cancelled.isCancelled, true);
      expect(PaymentStatus.cancelled.isCancellable, false);
    });
  });
}
