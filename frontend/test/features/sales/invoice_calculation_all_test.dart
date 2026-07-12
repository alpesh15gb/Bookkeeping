// Tests for InvoiceCalculationService.calculateAll — multi-line totals.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/services/invoice_calculation_service.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';

void main() {
  const calc = InvoiceCalculationService();
  const _eps = 0.001;

  group('calculateAll', () {
    test('single line matches calculateLine', () {
      const lines = [
        InvoiceLine(
          productId: 'p1',
          hsnSac: '72141000',
          gstRate: 18,
          quantity: 10,
          rate: 100,
        ),
      ];
      final r = calc.calculateAll(lines: lines);
      expect(r.lines.length, 1);
      expect(r.lines[0].total, closeTo(1180, _eps));
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.discountTotal, closeTo(0, _eps));
      expect(r.totalTax, closeTo(180, _eps));
      expect(r.total, closeTo(1180, _eps));
    });

    test('multi-line with header discount 10%', () {
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1234',
          gstRate: 18,
          quantity: 2,
          rate: 500,
        ),
        InvoiceLine(
          productId: 'b',
          hsnSac: '5678',
          gstRate: 12,
          quantity: 5,
          rate: 100,
        ),
      ];
      // line a: subtotal=1000, gst=180, total=1180
      // line b: subtotal=500, gst=60, total=560
      // subtotal=1500, discount=150, taxable=1350, tax=240, total=1590
      final r = calc.calculateAll(lines: lines, discountRate: 10);
      expect(r.subtotal, closeTo(1500, _eps));
      expect(r.discountTotal, closeTo(150, _eps));
      expect(r.totalTax, closeTo(240, _eps));
      expect(r.total, closeTo(1590, _eps));
    });

    test('shipping charges added to taxable', () {
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1234',
          gstRate: 18,
          quantity: 10,
          rate: 100,
        ),
      ];
      final r = calc.calculateAll(
        lines: lines,
        discountRate: 5,
        shippingCharges: 40,
      );
      // subtotal=1000, discount=50, shipping=40
      // taxable base for total = 990
      // line GST = 180 (cgst 90 + sgst 90)
      // total = 990 + 180 = 1170
      expect(r.subtotal, closeTo(1000, _eps));
      expect(r.discountTotal, closeTo(50, _eps));
      expect(r.totalTax, closeTo(180, _eps)); // line GST only
      expect(r.total, closeTo(1170, _eps)); // (1000-50+40) + 180
    });

    test('multiple tax slabs 5+12+18+28%', () {
      const lines = [
        InvoiceLine(
          productId: 'a',
          hsnSac: '1001',
          gstRate: 5,
          quantity: 10,
          rate: 100,
        ),
        InvoiceLine(
          productId: 'b',
          hsnSac: '1002',
          gstRate: 12,
          quantity: 10,
          rate: 100,
        ),
        InvoiceLine(
          productId: 'c',
          hsnSac: '1003',
          gstRate: 18,
          quantity: 10,
          rate: 100,
        ),
        InvoiceLine(
          productId: 'd',
          hsnSac: '1004',
          gstRate: 28,
          quantity: 10,
          rate: 100,
        ),
      ];
      final r = calc.calculateAll(lines: lines);
      expect(r.subtotal, closeTo(4000, _eps));
      expect(r.totalTax, closeTo(630, _eps));
      expect(r.total, closeTo(4630, _eps));
    });

    test('500 lines performance', () {
      final lines = List.generate(
        500,
        (i) => InvoiceLine(
          productId: 'p$i',
          hsnSac: '1234',
          gstRate: 18,
          quantity: 1,
          rate: 100,
        ),
      );
      final r = calc.calculateAll(lines: lines);
      expect(r.subtotal, closeTo(50000, _eps));
      expect(r.totalTax, closeTo(9000, _eps));
      expect(r.total, closeTo(59000, _eps));
    });
  });
}
