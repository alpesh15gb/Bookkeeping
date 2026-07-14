// Tests for InvoiceCalculationService — pure math, no UI dependencies.
// These tests verify GST accuracy, rounding, discount, and multi-line totals.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/services/invoice_calculation_service.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';

void main() {
  const calc = InvoiceCalculationService();
  const _eps = 0.001;

  group('calculateLine', () {
    test('CGST+SGST intra-state 18%', () {
      const line = InvoiceLine(
        productId: 'p1',
        hsnSac: '72141000',
        gstRate: 18,
        quantity: 10,
        rate: 100,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.cgstAmount, closeTo(90, _eps));
      expect(r.sgstAmount, closeTo(90, _eps));
      expect(r.igstAmount, closeTo(0, _eps));
      expect(r.total, closeTo(1180, _eps));
    });

    test('zero quantity', () {
      const line = InvoiceLine(
        productId: 'p3',
        hsnSac: '12345678',
        gstRate: 18,
        quantity: 0,
        rate: 100,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(0, _eps));
      expect(r.total, closeTo(0, _eps));
    });

    test('zero price', () {
      const line = InvoiceLine(
        productId: 'p4',
        hsnSac: '12345678',
        gstRate: 18,
        quantity: 10,
        rate: 0,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(0, _eps));
      expect(r.total, closeTo(0, _eps));
    });

    test('fixed 100 currency-unit discount', () {
      const line = InvoiceLine(
        productId: 'p5',
        hsnSac: '12345678',
        gstRate: 18,
        quantity: 10,
        rate: 100,
        discount: 100,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(900, _eps));
      expect(r.cgstAmount, closeTo(81, _eps));
      expect(r.total, closeTo(1062, _eps));
    });

    test('fixed 10 currency-unit discount', () {
      const line = InvoiceLine(
        productId: 'p6',
        hsnSac: '12345678',
        gstRate: 18,
        quantity: 10,
        rate: 100,
        discount: 10,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(990, _eps));
      expect(r.cgstAmount, closeTo(89.1, _eps));
      expect(r.total, closeTo(1168.2, _eps));
    });

    test('6% GST low rate', () {
      const line = InvoiceLine(
        productId: 'p7',
        hsnSac: '12345678',
        gstRate: 6,
        quantity: 100,
        rate: 50,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(5000, _eps));
      expect(r.cgstAmount, closeTo(150, _eps));
      expect(r.total, closeTo(5300, _eps));
    });

    test('rounding to 2 places', () {
      const line = InvoiceLine(
        productId: 'p8',
        hsnSac: '12345678',
        gstRate: 18,
        quantity: 3,
        rate: 49.99,
      );
      // subtotal=149.97, gst=149.97*18%=26.9946, cgst=13.4973→13.50, total=149.97+26.9946→176.96
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(149.97, _eps));
      expect(r.cgstAmount, closeTo(13.50, _eps));
      expect(r.total, closeTo(176.96, _eps));
    });
  });
}
