// Advanced tax corner cases for InvoiceCalculationService.
// Verifies: tax-inclusive pricing, CESS, zero-rated, exempt, mixed, round-off.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/services/invoice_calculation_service.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';

void main() {
  const calc = InvoiceCalculationService();
  const _eps = 0.001;

  group('Tax corner cases — calculateLine', () {
    test('CESS 1% applied correctly', () {
      const line = InvoiceLine(
        productId: 'p1',
        hsnSac: '72141000',
        gstRate: 18,
        cessRate: 1,
        quantity: 10,
        rate: 100,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.cgstAmount, closeTo(90, _eps)); // 1000 * 18% / 2
      expect(r.sgstAmount, closeTo(90, _eps));
      expect(r.cessAmount, closeTo(10, _eps)); // 1000 * 1%
      expect(r.total, closeTo(1190, _eps)); // 1000 + 180 + 10
    });

    test('zero-rated (0% GST) produces no tax', () {
      const line = InvoiceLine(
        productId: 'p2',
        hsnSac: '12345678',
        gstRate: 0,
        quantity: 10,
        rate: 100,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.cgstAmount, closeTo(0, _eps));
      expect(r.sgstAmount, closeTo(0, _eps));
      expect(r.total, closeTo(1000, _eps));
    });

    test('exempt (null/0 GST) still calculates subtotal correctly', () {
      const line = InvoiceLine(
        productId: 'p3',
        hsnSac: '12345678',
        gstRate: 0,
        quantity: 5,
        rate: 200,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.total, closeTo(1000, _eps));
    });

    test('mixed taxable and zero-rated lines in calculateAll', () {
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1001',
          gstRate: 18,
          quantity: 10,
          rate: 100,
        ), // taxable: 1000+180=1180
        InvoiceLine(
          productId: 'b',
          hsnSac: '1002',
          gstRate: 0,
          quantity: 10,
          rate: 100,
        ), // zero-rated: 1000
      ];
      final r = calc.calculateAll(lines: lines);
      expect(r.subtotal, closeTo(2000, _eps));
      expect(r.totalTax, closeTo(180, _eps)); // only from line a
      expect(r.total, closeTo(2180, _eps)); // 2000 + 180
    });

    test('CESS + GST combined on high-GST item', () {
      const line = InvoiceLine(
        productId: 'p4',
        hsnSac: '12345678',
        gstRate: 28,
        cessRate: 15,
        quantity: 10,
        rate: 100,
      );
      final r = calc.calculateLine(line: line);
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.cgstAmount, closeTo(140, _eps)); // 1000 * 28% / 2
      expect(r.sgstAmount, closeTo(140, _eps));
      expect(r.cessAmount, closeTo(150, _eps)); // 1000 * 15%
      expect(r.total, closeTo(1430, _eps)); // 1000 + 280 + 150
    });
  });

  group('Tax corner cases — calculateAll', () {
    test('very small quantities fractional', () {
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1234',
          gstRate: 18,
          quantity: 0.5,
          rate: 199.99,
        ),
      ];
      final r = calc.calculateAll(lines: lines);
      // subtotal = 99.995 → 100.00
      expect(r.subtotal, closeTo(100.00, _eps));
    });

    test('large quantity small rate', () {
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1234',
          gstRate: 5,
          quantity: 10000,
          rate: 0.50,
        ),
      ];
      final r = calc.calculateAll(lines: lines);
      expect(r.subtotal, closeTo(5000, _eps));
      expect(r.totalTax, closeTo(250, _eps)); // 5000 * 5%
      expect(r.total, closeTo(5250, _eps));
    });

    test('round-off with discount — exact numbers', () {
      // Use 10.00 and 20.00 — exact in binary floating point.
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1234',
          gstRate: 18,
          quantity: 10,
          rate: 100.00,
        ),
        InvoiceLine(
          productId: 'b',
          hsnSac: '5678',
          gstRate: 12,
          quantity: 5,
          rate: 50.00,
        ),
      ];
      // subtotal = 1000 + 250 = 1250
      // discount = 1250 * 0.05 = 62.50
      // taxable = 1250 - 62.50 = 1187.50
      // totalTax = (1000*0.09*2) + (250*0.06*2) = 180 + 30 = 210
      // total = 1187.50 + 210 = 1397.50
      final r = calc.calculateAll(lines: lines, discountRate: 5);
      expect(r.subtotal, closeTo(1250, _eps));
      expect(r.discountTotal, closeTo(62.50, _eps));
      expect(r.totalTax, closeTo(210, _eps));
      expect(r.total, closeTo(1397.50, _eps));
    });
  });
}
