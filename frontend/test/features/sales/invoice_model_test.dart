// Tests for Invoice, InvoiceListItem, InvoiceLine model JSON parsing.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/models/invoice.dart';
import 'package:apexbooks/features/sales/models/invoice_line.dart';
import 'package:apexbooks/features/sales/models/invoice_status.dart';

void main() {
  group('InvoiceLine.fromResponse', () {
    test('parses full response', () {
      final line = InvoiceLine.fromResponse({
        'id': 'line-1',
        'product_id': 'prod-1',
        'product_name': 'Steel Rod',
        'quantity': 10,
        'rate': 150.0,
        'discount': 10.0,
        'hsn_sac': '72141000',
        'gst_rate': 18,
        'subtotal': 1500.0,
        'cgst_rate': 9.0,
        'cgst_amount': 121.5,
        'sgst_rate': 9.0,
        'sgst_amount': 121.5,
        'igst_rate': 0,
        'igst_amount': 0,
        'total': 1743.0,
      });
      expect(line.id, 'line-1');
      expect(line.productId, 'prod-1');
      expect(line.productName, 'Steel Rod');
      expect(line.quantity, 10);
      expect(line.rate, 150.0);
      expect(line.discount, 10.0);
      expect(line.hsnSac, '72141000');
      expect(line.gstRate, 18);
      expect(line.subtotal, 1500.0);
      expect(line.cgstAmount, 121.5);
      expect(line.sgstAmount, 121.5);
      expect(line.total, 1743.0);
    });

    test('defaults on minimal response', () {
      final line = InvoiceLine.fromResponse({'product_id': 'p1'});
      expect(line.productId, 'p1');
      expect(line.quantity, 1);
      expect(line.rate, 0);
      expect(line.gstRate, 0);
      expect(line.subtotal, 0);
      expect(line.total, 0);
    });

    test('toCreatePayload excludes null fields', () {
      const line = InvoiceLine(
        productId: 'p1',
        hsnSac: '7214',
        gstRate: 18,
        quantity: 2,
        rate: 100,
      );
      final payload = line.toCreatePayload();
      expect(payload['product_id'], 'p1');
      expect(payload['quantity'], 2);
      expect(payload['rate'], 100);
      expect(payload['hsn_sac'], '7214');
      expect(payload['gst_rate'], 18);
      expect(payload.containsKey('description'), false);
      expect(payload.containsKey('id'), false);
    });
  });

  group('Invoice.fromJson', () {
    test('parses full response', () {
      final json = {
        'id': 'inv-1',
        'tenant_id': 'tenant-1',
        'contact_id': 'contact-1',
        'invoice_number': 'INV-001',
        'issue_date': '2025-07-01',
        'due_date': '2025-07-31',
        'status': 'POSTED',
        'subtotal': 1000.0,
        'discount_total': 50.0,
        'shipping_charges': 40.0,
        'cgst_amount': 90.0,
        'sgst_amount': 90.0,
        'igst_amount': 0,
        'cess_amount': 0,
        'round_off': 0,
        'total': 1170.0,
        'amount_paid': 500.0,
        'pos_state_code': '27',
        'irn': null,
        'e_invoice_status': 'PENDING',
        'notes': 'Thank you',
        'terms_and_conditions': 'Net 30',
        'reference_number': 'PO-123',
        'is_gst_inclusive': false,
        'is_rcm': false,
        'supply_type': 'DOMESTIC',
        'currency': 'INR',
        'exchange_rate': 1,
        'tds_rate': 0,
        'tds_amount': 0,
        'tcs_rate': 0,
        'tcs_amount': 0,
        'lines': [],
        'created_at': '2025-07-01T10:00:00Z',
        'updated_at': '2025-07-01T11:00:00Z',
      };
      final inv = Invoice.fromJson(json);
      expect(inv.id, 'inv-1');
      expect(inv.invoiceNumber, 'INV-001');
      expect(inv.status, InvoiceStatus.posted);
      expect(inv.subtotal, 1000.0);
      expect(inv.total, 1170.0);
      expect(inv.amountPaid, 500.0);
      expect(inv.outstanding, 670.0);
      expect(inv.netAmount, 990.0); // 1000-50+40
      expect(inv.totalTax, 180.0);
      expect(inv.lines, isEmpty);
    });
  });

  group('InvoiceListItem.fromJson', () {
    test('parses list response', () {
      final item = InvoiceListItem.fromJson({
        'id': 'inv-2',
        'contact_id': 'contact-2',
        'invoice_number': 'INV-002',
        'issue_date': '2025-07-05',
        'due_date': '2025-08-05',
        'status': 'PARTIALLY_PAID',
        'total': 5000.0,
        'amount_paid': 2000.0,
        'contact_name': 'Acme Corp',
        'created_at': '2025-07-05T08:00:00Z',
      });
      expect(item.id, 'inv-2');
      expect(item.invoiceNumber, 'INV-002');
      expect(item.status, InvoiceStatus.partiallyPaid);
      expect(item.total, 5000.0);
      expect(item.outstanding, 3000.0);
      expect(item.contactName, 'Acme Corp');
    });
  });

  group('InvoiceStatus computed getters', () {
    test('draft is editable and deletable', () {
      expect(InvoiceStatus.draft.isEditable, true);
      expect(InvoiceStatus.draft.isDeletable, true);
      expect(InvoiceStatus.draft.isFinalized, false);
      expect(InvoiceStatus.draft.isCancellable, false);
    });

    test('posted is finalized and cancellable', () {
      expect(InvoiceStatus.posted.isFinalized, true);
      expect(InvoiceStatus.posted.isCancellable, true);
      expect(InvoiceStatus.posted.isEditable, false);
      expect(InvoiceStatus.posted.isDeletable, false);
    });

    test('cancelled is not final, not editable', () {
      expect(InvoiceStatus.cancelled.isFinalized, false);
      expect(InvoiceStatus.cancelled.isEditable, false);
      expect(InvoiceStatus.cancelled.isDeletable, false);
    });
  });
}
