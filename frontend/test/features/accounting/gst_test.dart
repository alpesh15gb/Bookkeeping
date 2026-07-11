// Tests for GST Engine — output, input, net liability.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/gst/models/gst_report.dart';

void main() {
  group('GstLine', () {
    test('fromJson', () {
      final line = GstLine.fromJson({
        'invoice_number': 'INV-001',
        'invoice_date': '2025-07-01',
        'contact_name': 'Acme Corp',
        'taxable_value': '10000',
        'cgst': '900',
        'sgst': '900',
        'igst': '0',
        'cess': '0',
        'total_tax': '1800',
      });
      expect(line.invoiceNumber, 'INV-001');
      expect(line.taxableValue, 10000);
      expect(line.cgst, 900);
      expect(line.sgst, 900);
      expect(line.totalTax, 1800);
    });
  });

  group('GstReport', () {
    test('fromJson', () {
      final report = GstReport.fromJson({
        'total_output_gst': '18000',
        'total_input_gst': '12000',
        'net_gst_liability': '6000',
        'total_reverse_charge': '0',
        'output_gst_lines': [
          {
            'invoice_number': 'INV-001',
            'taxable_value': '100000',
            'cgst': '9000',
            'sgst': '9000',
            'total_tax': '18000',
          },
        ],
        'input_gst_lines': [
          {
            'invoice_number': 'BILL-001',
            'taxable_value': '66667',
            'cgst': '6000',
            'sgst': '6000',
            'total_tax': '12000',
          },
        ],
      });
      expect(report.totalOutputGst, 18000);
      expect(report.totalInputGst, 12000);
      expect(report.netGstLiability, 6000);
      expect(report.outputGstLines.length, 1);
      expect(report.inputGstLines.length, 1);
    });
  });
}
