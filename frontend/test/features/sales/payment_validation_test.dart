// Tests for PaymentValidationService.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/payments/services/payment_validation_service.dart';
import 'package:apexbooks/features/sales/payments/models/payment_models.dart';
import 'package:apexbooks/features/sales/payments/models/outstanding_invoice.dart';
import 'package:apexbooks/features/sales/payments/models/payment_enums.dart';

void main() {
  const validation = PaymentValidationService();

  group('validateForCreate', () {
    const validInvoice = OutstandingInvoice(
      id: 'inv-1',
      invoiceNumber: 'INV-001',
      total: 1000,
      amountPaid: 0,
      dueDate: '2025-08-01',
      contactName: 'A',
    );
    const validAlloc = PaymentAllocation(invoiceId: 'inv-1', amount: 500);

    test('rejects null contactId', () {
      final r = validation.validateForCreate(
        contactId: null,
        paymentDate: '2025-07-01',
        paymentMode: 'BANK',
        amount: 500,
        allocations: [validAlloc],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, false);
      expect(r.$2, contains('Customer'));
    });

    test('rejects empty paymentDate', () {
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '',
        paymentMode: 'BANK',
        amount: 500,
        allocations: [validAlloc],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, false);
    });

    test('rejects zero amount', () {
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '2025-07-01',
        paymentMode: 'BANK',
        amount: 0,
        allocations: [validAlloc],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, false);
    });

    test('accepts empty allocations as customer advance', () {
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '2025-07-01',
        paymentMode: 'BANK',
        amount: 500,
        allocations: const [],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, true);
    });

    test('rejects invalid payment mode', () {
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '2025-07-01',
        paymentMode: 'INVALID',
        amount: 500,
        allocations: [validAlloc],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, false);
    });

    test('rejects allocation exceeding outstanding', () {
      const bigAlloc = PaymentAllocation(invoiceId: 'inv-1', amount: 2000);
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '2025-07-01',
        paymentMode: 'BANK',
        amount: 2000,
        allocations: [bigAlloc],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, false);
      expect(r.$2, contains('exceeds outstanding'));
    });

    test('rejects allocation total > payment amount', () {
      const alloc1 = PaymentAllocation(invoiceId: 'inv-1', amount: 600);
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '2025-07-01',
        paymentMode: 'BANK',
        amount: 500,
        allocations: [alloc1],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, false);
      expect(r.$2, contains('exceeds payment'));
    });

    test('accepts valid input', () {
      final r = validation.validateForCreate(
        contactId: 'c1',
        paymentDate: '2025-07-01',
        paymentMode: 'BANK',
        amount: 500,
        allocations: [validAlloc],
        availableInvoices: [validInvoice],
      );
      expect(r.$1, true);
      expect(r.$2, isNull);
    });
  });

  group('validateCancel', () {
    test('rejects already cancelled', () {
      final p = Payment(id: 'p1', status: PaymentStatus.cancelled);
      final r = validation.validateCancel(p);
      expect(r.$1, false);
    });

    test('allows active', () {
      final p = Payment(id: 'p1', status: PaymentStatus.active);
      final r = validation.validateCancel(p);
      expect(r.$1, true);
    });
  });
}
