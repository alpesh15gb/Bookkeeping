// Tests for InvoiceValidationService — business rule validation.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/services/invoice_validation_service.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';
import 'package:apexbooks/features/sales/models/invoice_status.dart';

void main() {
  const validation = InvoiceValidationService();

  group('validateForSave', () {
    const validLine = InvoiceLine(
      productId: 'p1',
      hsnSac: '7214',
      gstRate: 18,
      quantity: 1,
      rate: 100,
    );

    test('rejects null contactId', () {
      final r = validation.validateForSave(
        contactId: null,
        lines: [validLine],
        posStateCode: '27',
      );
      expect(r.$1, false);
      expect(r.$2, contains('Customer'));
    });

    test('rejects empty posStateCode', () {
      final r = validation.validateForSave(
        contactId: 'c1',
        lines: [validLine],
        posStateCode: '',
      );
      expect(r.$1, false);
      expect(r.$2, contains('Place of Supply'));
    });

    test('rejects empty lines', () {
      final r = validation.validateForSave(
        contactId: 'c1',
        lines: [],
        posStateCode: '27',
      );
      expect(r.$1, false);
      expect(r.$2, contains('line item'));
    });

    test('rejects line with empty productId', () {
      final r = validation.validateForSave(
        contactId: 'c1',
        lines: [const InvoiceLine(productId: '', hsnSac: '1234', gstRate: 18)],
        posStateCode: '27',
      );
      expect(r.$1, false);
      expect(r.$2, contains('Product'));
    });

    test('rejects zero quantity', () {
      final r = validation.validateForSave(
        contactId: 'c1',
        lines: [
          const InvoiceLine(
            productId: 'p1',
            hsnSac: '1234',
            gstRate: 18,
            quantity: 0,
            rate: 100,
          ),
        ],
        posStateCode: '27',
      );
      expect(r.$1, false);
      expect(r.$2, contains('Quantity'));
    });

    test('rejects short HSN', () {
      final r = validation.validateForSave(
        contactId: 'c1',
        lines: [const InvoiceLine(productId: 'p1', hsnSac: '12', gstRate: 18)],
        posStateCode: '27',
      );
      expect(r.$1, false);
      expect(r.$2, contains('HSN'));
    });

    test('accepts valid input', () {
      final r = validation.validateForSave(
        contactId: 'c1',
        lines: [validLine],
        posStateCode: '27',
      );
      expect(r.$1, true);
      expect(r.$2, isNull);
    });
  });

  group('validateStatusTransition', () {
    test('draft → posted allowed', () {
      final r = validation.validateStatusTransition(
        InvoiceStatus.draft,
        InvoiceStatus.posted,
      );
      expect(r.$1, true);
    });

    test('posted → cancelled allowed', () {
      final r = validation.validateStatusTransition(
        InvoiceStatus.posted,
        InvoiceStatus.cancelled,
      );
      expect(r.$1, true);
    });

    test('draft → cancelled rejected', () {
      final r = validation.validateStatusTransition(
        InvoiceStatus.draft,
        InvoiceStatus.cancelled,
      );
      expect(r.$1, false);
    });

    test('posted → draft rejected', () {
      final r = validation.validateStatusTransition(
        InvoiceStatus.posted,
        InvoiceStatus.draft,
      );
      expect(r.$1, false);
    });
  });
}
