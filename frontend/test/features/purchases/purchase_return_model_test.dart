import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return_line.dart';

void main() {
  test(
    'purchase return create payload matches source-bound backend contract',
    () {
      const purchaseReturn = PurchaseReturn(
        id: '',
        billId: 'bill-1',
        contactId: 'vendor-1',
        posStateCode: '29',
        returnDate: '2026-07-14',
        notes: 'Damaged in transit',
        lines: [
          PurchaseReturnLine(
            billLineId: 'bill-line-1',
            productId: 'product-1',
            quantityReturned: 2,
            maximumQuantity: 5,
            rate: 100,
            hsnSac: '84713010',
            gstRate: 18,
            reason: 'Damaged',
          ),
        ],
      );

      final payload = purchaseReturn.toCreatePayload();
      expect(payload['bill_id'], 'bill-1');
      expect(payload['contact_id'], 'vendor-1');
      expect(payload['issue_date'], '2026-07-14');
      expect(payload['pos_state_code'], '29');
      expect(payload.containsKey('return_date'), isFalse);
      final line =
          (payload['line_items'] as List).single as Map<String, dynamic>;
      expect(line['bill_line_id'], 'bill-line-1');
      expect(line['quantity'], 2);
      expect(line['hsn_sac'], '84713010');
      expect(line.containsKey('quantity_returned'), isFalse);
    },
  );

  test('purchase return response parses authoritative tax and issue date', () {
    final purchaseReturn = PurchaseReturn.fromJson({
      'id': 'return-1',
      'return_number': 'PR/26/1',
      'bill_id': 'bill-1',
      'contact_id': 'vendor-1',
      'issue_date': '2026-07-14',
      'pos_state_code': '29',
      'status': 'POSTED',
      'subtotal': '100.0000',
      'cgst_amount': '0',
      'sgst_amount': '0',
      'igst_amount': '18.0000',
      'utgst_amount': '0',
      'cess_amount': '0',
      'total': '118.0000',
      'lines': [
        {
          'id': 'line-1',
          'bill_line_id': 'bill-line-1',
          'product_id': 'product-1',
          'quantity': '1.0000',
          'rate': '100.0000',
          'hsn_sac': '84713010',
          'gst_rate': '18',
          'subtotal': '100',
          'igst_amount': '18',
          'total': '118',
          'description': 'Damaged',
        },
      ],
    });

    expect(purchaseReturn.returnDate, '2026-07-14');
    expect(purchaseReturn.totalTax, 18);
    expect(purchaseReturn.lines.single.quantityReturned, 1);
    expect(purchaseReturn.lines.single.reason, 'Damaged');
  });
}
