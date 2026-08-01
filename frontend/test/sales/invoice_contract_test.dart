/// Contract verification tests for invoice models.
///
/// Fixtures derived from:
///   backend/src/schemas/document.py — InvoiceResponse, InvoiceListResponse,
///     InvoiceLineResponse
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/models/invoice.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';
import 'package:apexbooks/features/sales/models/invoice_status.dart';

/// Fixture: backend GET /invoices/{id} response
///
/// Based on InvoiceResponse (document.py lines 158–192):
///   id, tenant_id, contact_id, invoice_number, issue_date, due_date,
///   pos_state_code, status, subtotal, discount_total, cgst_amount,
///   sgst_amount, igst_amount, utgst_amount, cess_amount, round_off,
///   total, amount_paid, irn?, qr_code?, notes?, terms_and_conditions?,
///   reference_number?, tds_rate, tds_amount, tcs_rate, tcs_amount,
///   created_at, updated_at, lines[]
final Map<String, dynamic> kInvoiceDetailPayload = {
  'id': 'inv-a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'tenant_id': 't1a2b3c4-d5e6-7890-abcd-ef1234567890',
  'contact_id': 'c1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'invoice_number': 'INV-2026-001',
  'issue_date': '2026-07-01',
  'due_date': '2026-07-31',
  'pos_state_code': '27',
  'status': 'POSTED',
  'is_gst_inclusive': false,
  'is_rcm': false,
  'supply_type': 'DOMESTIC',
  'currency': 'INR',
  'exchange_rate': '1.000000',
  'subtotal': '100000.0000',
  'discount_total': '5000.0000',
  'shipping_charges': '0.0000',
  'cgst_amount': '4275.0000',
  'sgst_amount': '4275.0000',
  'igst_amount': '0.0000',
  'utgst_amount': '0.0000',
  'cess_amount': '0.0000',
  'round_off': '-0.50',
  'total': '103549.5000',
  'amount_paid': '50000.0000',
  'tds_rate': '0.00',
  'tds_amount': '0.0000',
  'tcs_rate': '0.00',
  'tcs_amount': '0.0000',
  'irn': null,
  'qr_code': null,
  'e_invoice_status': 'PENDING',
  'e_invoice_error': null,
  'notes': 'Thank you for your business',
  'terms_and_conditions': 'Payment due within 30 days',
  'reference_number': 'PO-2026-001',
  'sales_person_id': null,
  'contact_name': 'Acme Corp Pvt Ltd',
  'created_at': '2026-07-01T10:00:00Z',
  'updated_at': '2026-07-01T10:00:00Z',
  'lines': [
    {
      'id': 'il-b1c2d3e4-f5a6-7890-bcde-f12345678901',
      'product_id': 'p1b2c3d4-e5f6-7890-abcd-ef1234567890',
      'product_name': 'Consulting Services - Level 1',
      'description': 'Professional consulting for July 2026',
      'quantity': '10.0000',
      'rate': '10000.0000',
      'discount': '500.0000',
      'hsn_sac': '998313',
      'gst_rate': '18.00',
      'subtotal': '100000.0000',
      'cgst_rate': '9.00',
      'cgst_amount': '4275.0000',
      'sgst_rate': '9.00',
      'sgst_amount': '4275.0000',
      'igst_rate': '0.00',
      'igst_amount': '0.0000',
      'utgst_rate': '0.00',
      'utgst_amount': '0.0000',
      'cess_rate': '0.00',
      'cess_amount': '0.0000',
      'total': '94950.0000',
    },
  ],
};

/// Fixture: backend GET /invoices list response item
///
/// Based on InvoiceListResponse (document.py lines 194–210)
final Map<String, dynamic> kInvoiceListItemPayload = {
  'id': 'inv-a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'contact_id': 'c1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'invoice_number': 'INV-2026-001',
  'issue_date': '2026-07-01',
  'due_date': '2026-07-31',
  'status': 'POSTED',
  'total': '103549.5000',
  'amount_paid': '50000.0000',
  'contact_name': 'Acme Corp Pvt Ltd',
  'reference_number': 'PO-2026-001',
  'created_at': '2026-07-01T10:00:00Z',
};

void main() {
  group('Invoice — contract', () {
    test('parses full invoice detail response from backend', () {
      final inv = Invoice.fromJson(kInvoiceDetailPayload);

      expect(inv.id, 'inv-a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(inv.invoiceNumber, 'INV-2026-001');
      expect(inv.status, InvoiceStatus.posted);
      expect(inv.subtotal, 100000.0);
      expect(inv.discountTotal, 5000.0);
      expect(inv.cgstAmount, 4275.0);
      expect(inv.sgstAmount, 4275.0);
      expect(inv.total, 103549.50);
      expect(inv.amountPaid, 50000.0);
      expect(inv.outstanding, 53549.50);
    });

    test('parses Decimal-as-string values correctly', () {
      final inv = Invoice.fromJson(kInvoiceDetailPayload);

      // Backend sends Numeric(15,4) values as strings — parseDoubleSafe must handle
      expect(inv.subtotal, isA<double>());
      expect(inv.total, isA<double>());
      expect(inv.roundOff, closeTo(-0.5, 0.001));
    });

    test('parses line items correctly', () {
      final inv = Invoice.fromJson(kInvoiceDetailPayload);

      expect(inv.lines.length, 1);
      final line = inv.lines.first;
      expect(line.productName, 'Consulting Services - Level 1');
      expect(line.quantity, 10.0);
      expect(line.rate, 10000.0);
      expect(line.discount, 500.0);
      expect(line.hsnSac, '998313');
      expect(line.gstRate, 18.0);
      expect(line.total, 94950.0);
    });

    test('parses GST breakdown correctly', () {
      final inv = Invoice.fromJson(kInvoiceDetailPayload);
      final line = inv.lines.first;

      expect(line.cgstRate, 9.0);
      expect(line.cgstAmount, 4275.0);
      expect(line.sgstRate, 9.0);
      expect(line.sgstAmount, 4275.0);
      expect(line.igstAmount, 0.0);
    });

    test('handles null IRN and QR code for non-e-invoice', () {
      final inv = Invoice.fromJson(kInvoiceDetailPayload);

      expect(inv.irn, isNull);
      expect(inv.qrCode, isNull);
    });

    test('parses InvoiceStatus from backend string values', () {
      final statusValues = {
        'DRAFT': InvoiceStatus.draft,
        'POSTED': InvoiceStatus.posted,
        'SENT': InvoiceStatus.sent,
        'PARTIALLY_PAID': InvoiceStatus.partiallyPaid,
        'PAID': InvoiceStatus.paid,
        'CANCELLED': InvoiceStatus.cancelled,
        'OVERDUE': InvoiceStatus.overdue,
      };

      for (final entry in statusValues.entries) {
        expect(InvoiceStatus.fromString(entry.key), entry.value);
      }
    });

    test('InvoiceStatus.fromString defaults to draft for unknown values', () {
      expect(InvoiceStatus.fromString('UNKNOWN'), InvoiceStatus.draft);
      expect(InvoiceStatus.fromString(null), InvoiceStatus.draft);
    });

    test('handles empty lines list', () {
      final payload = Map<String, dynamic>.from(kInvoiceDetailPayload);
      payload['lines'] = [];

      final inv = Invoice.fromJson(payload);

      expect(inv.lines, isEmpty);
    });

    test('tolerates unknown extra fields', () {
      final payload = Map<String, dynamic>.from(kInvoiceDetailPayload);
      payload['unknown_field'] = 'should not crash';

      expect(() => Invoice.fromJson(payload), returnsNormally);
    });

    test('computes totalTax correctly', () {
      final inv = Invoice.fromJson(kInvoiceDetailPayload);

      // CGST 4275 + SGST 4275 = 8550. No IGST/UTGST/CESS
      expect(inv.totalTax, closeTo(8550.0, 0.001));
    });

    test('toCreatePayload produces correct API shape', () {
      final line = kInvoiceDetailPayload['lines'][0] as Map<String, dynamic>;
      final invoiceLine = InvoiceLine.fromResponse(line);

      final payload = invoiceLine.toCreatePayload();

      expect(payload['product_id'], 'p1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(payload['quantity'], 10.0);
      expect(payload['rate'], 10000.0);
      expect(payload['discount'], 500.0);
      expect(payload['hsn_sac'], '998313');
      expect(payload['gst_rate'], 18.0);
      // Should NOT include computed fields
      expect(payload.containsKey('cgst_amount'), isFalse);
      expect(payload.containsKey('total'), isFalse);
    });
  });

  group('InvoiceListItem — contract', () {
    test('parses list item from backend', () {
      final item = InvoiceListItem.fromJson(kInvoiceListItemPayload);

      expect(item.id, 'inv-a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(item.invoiceNumber, 'INV-2026-001');
      expect(item.contactName, 'Acme Corp Pvt Ltd');
      expect(item.total, 103549.50);
      expect(item.amountPaid, 50000.0);
      expect(item.outstanding, 53549.50);
      expect(item.status, InvoiceStatus.posted);
    });

    test('parses Decimal-as-string for total', () {
      final item = InvoiceListItem.fromJson(kInvoiceListItemPayload);

      expect(item.total, isA<double>());
      expect(item.total, 103549.50);
    });

    test('handles null reference_number', () {
      final payload = Map<String, dynamic>.from(kInvoiceListItemPayload);
      payload['reference_number'] = null;

      final item = InvoiceListItem.fromJson(payload);

      expect(item.referenceNumber, isNull);
    });
  });
}
