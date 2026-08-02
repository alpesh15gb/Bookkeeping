// Invoice detail response parsing tests.
//
// Guards the contract between the backend `InvoiceResponse` and the Flutter
// `Invoice` DTO used by InvoiceDetailScreen. The backend embeds the customer
// as `contact: {name, ...}` while the list embeds a flat `contact_name`, and
// many optional fields are nullable/absent — parsing must tolerate all of it
// without throwing or losing the customer name.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/models/invoice.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';
import 'package:apexbooks/features/sales/models/invoice_status.dart';

Map<String, dynamic> _lineJson() => {
  'id': 'line-1',
  'product_id': 'prod-1',
  'product_name': 'MacBook Pro M3 Max',
  'description': 'MacBook Pro M3 Max',
  'quantity': '1',
  'rate': '5000.0000',
  'discount': '0.0000',
  'hsn_sac': '84713010',
  'gst_rate': '18.00',
  'unit': 'PCS',
  'subtotal': '5000.0000',
  'cgst_rate': '9.00',
  'cgst_amount': '450.0000',
  'sgst_rate': '9.00',
  'sgst_amount': '450.0000',
  'igst_rate': '0.00',
  'igst_amount': '0.0000',
  'utgst_rate': '0.00',
  'utgst_amount': '0.0000',
  'cess_rate': '0.00',
  'cess_amount': '0.0000',
  'total': '5900.0000',
};

Map<String, dynamic> _detailJson() => {
  'id': '4a5d4d5f-8b2f-4e3a-9b1c-000000000001',
  'tenant_id': '00000000-0000-0000-0000-0000000000aa',
  'contact_id': '00000000-0000-0000-0000-0000000000bb',
  'invoice_number': 'INV/26-27/0001',
  'issue_date': '2026-08-03',
  'due_date': '2026-08-03',
  'status': 'DRAFT',
  'pos_state_code': '27',
  'billing_address': null,
  'shipping_address': null,
  'currency': 'INR',
  'exchange_rate': '1.000000',
  'is_gst_inclusive': false,
  'is_rcm': false,
  'supply_type': 'DOMESTIC',
  'tds_rate': '0.00',
  'tds_amount': '0.0000',
  'tcs_rate': '0.00',
  'tcs_amount': '0.0000',
  'subtotal': '5000.0000',
  'discount_total': '0.0000',
  'shipping_charges': '0.0000',
  'cgst_amount': '450.0000',
  'sgst_amount': '450.0000',
  'igst_amount': '0.0000',
  'utgst_amount': '0.0000',
  'cess_amount': '0.0000',
  'round_off': '0.0000',
  'total': '5900.0000',
  'amount_paid': '0.0000',
  'irn': null,
  'qr_code': null,
  'e_invoice_status': 'PENDING',
  'e_invoice_error': null,
  'notes': null,
  'terms_and_conditions': null,
  'reference_number': null,
  'sales_person_id': null,
  'created_at': '2026-08-03T10:00:00Z',
  'updated_at': '2026-08-03T10:00:00Z',
  'lines': [_lineJson()],
  'contact': {
    'id': '00000000-0000-0000-0000-0000000000bb',
    'name': 'Tata Consultancy Services Ltd',
    'email': 'finance@tcs.com',
    'billing_address': null,
    'state_code': null,
  },
};

void main() {
  group('Invoice.fromJson (detail response)', () {
    test('parses full detail response with embedded contact', () {
      final inv = Invoice.fromJson(_detailJson());
      expect(inv.id, '4a5d4d5f-8b2f-4e3a-9b1c-000000000001');
      expect(inv.invoiceNumber, 'INV/26-27/0001');
      expect(inv.status, InvoiceStatus.draft);
      expect(inv.posStateCode, '27');
      expect(inv.subtotal, 5000.0);
      expect(inv.total, 5900.0);
      expect(inv.cgstAmount, 450.0);
      expect(inv.sgstAmount, 450.0);
      expect(inv.lines.length, 1);
      expect(inv.lines[0].productName, 'MacBook Pro M3 Max');
      // Customer name falls back to the embedded contact object.
      expect(inv.customerName, 'Tata Consultancy Services Ltd');
      expect(inv.contactName, 'Tata Consultancy Services Ltd');
    });

    test('nullable optional fields do not throw', () {
      final inv = Invoice.fromJson(_detailJson());
      expect(inv.irn, isNull);
      expect(inv.qrCode, isNull);
      expect(inv.notes, isNull);
      expect(inv.termsAndConditions, isNull);
      expect(inv.referenceNumber, isNull);
      expect(inv.eInvoiceError, isNull);
      expect(inv.originStateCode, isNull);
      expect(inv.outstandingAmount, 5900.0);
    });

    test('empty payments list parses to empty list', () {
      final json = _detailJson()..['payments'] = <dynamic>[];
      final inv = Invoice.fromJson(json);
      expect(inv.payments, isEmpty);
    });

    test('empty optional e-invoice fields parse cleanly', () {
      final json = _detailJson()
        ..['irn'] = ''
        ..['qr_code'] = ''
        ..['e_invoice_status'] = 'GENERATED'
        ..['e_invoice_error'] = '';
      final inv = Invoice.fromJson(json);
      expect(inv.eInvoiceStatus, EInvoiceStatus.generated);
      expect(inv.irn, '');
    });

    test('flat contact_name is honored when present (list-style)', () {
      final json = _detailJson()
        ..remove('contact')
        ..['contact_name'] = 'Flat Customer';
      final inv = Invoice.fromJson(json);
      expect(inv.customerName, 'Flat Customer');
    });

    test('missing contact yields null name without throwing', () {
      final json = _detailJson()..remove('contact');
      final inv = Invoice.fromJson(json);
      expect(inv.customerName, isNull);
      expect(inv.lines.length, 1);
    });

    test('malformed/missing fields default safely', () {
      final inv = Invoice.fromJson(<String, dynamic>{});
      expect(inv.id, '');
      expect(inv.status, InvoiceStatus.draft);
      expect(inv.total, 0);
      expect(inv.lines, isEmpty);
      expect(inv.payments, isEmpty);
    });

    test('string decimals parse to doubles', () {
      final inv = Invoice.fromJson(_detailJson());
      expect(inv.cgstAmount, 450.0);
      expect(inv.sgstAmount, 450.0);
      expect(inv.roundOff, 0.0);
    });

    test('InvoiceLine.fromResponse parses backend line shape', () {
      final line = InvoiceLine.fromResponse(_lineJson());
      expect(line.productName, 'MacBook Pro M3 Max');
      expect(line.quantity, 1);
      expect(line.rate, 5000.0);
      expect(line.subtotal, 5000.0);
      expect(line.total, 5900.0);
    });
  });

  group('InvoiceListItem.fromJson (list response)', () {
    test('parses list item', () {
      final item = InvoiceListItem.fromJson({
        'id': 'inv-1',
        'contact_id': 'c-1',
        'invoice_number': 'INV/1',
        'issue_date': '2026-08-03',
        'due_date': '2026-08-03',
        'status': 'DRAFT',
        'total': '5900.0000',
        'amount_paid': '0.0000',
        'contact_name': 'Tata Consultancy Services Ltd',
        'created_at': '2026-08-03T10:00:00Z',
      });
      expect(item.id, 'inv-1');
      expect(item.invoiceNumber, 'INV/1');
      expect(item.status, InvoiceStatus.draft);
      expect(item.total, 5900.0);
      expect(item.outstanding, 5900.0);
      expect(item.customerName, 'Tata Consultancy Services Ltd');
    });
  });
}
