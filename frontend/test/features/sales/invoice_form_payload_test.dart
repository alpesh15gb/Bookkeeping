// InvoiceFormNotifier.save() payload contract tests.
//
// Verifies the draft-save request that InvoiceFormScreen sends:
//   - post_on_create is explicitly false (never auto-post from the form)
//   - required header fields and line items are serialized for the backend
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/sales/presentation/invoice_form_notifier.dart';
import 'package:apexbooks/features/sales/services/invoice_calculation_service.dart';
import 'package:apexbooks/features/sales/services/invoice_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    if (data is String) {
      lastBody = jsonDecode(data) as Map<String, dynamic>;
    } else if (data is Map) {
      lastBody = data.cast<String, dynamic>();
    }
    final body = jsonEncode({
      'id': 'inv-new',
      'invoice_number': 'INV/26-27/0001',
      'status': 'DRAFT',
      'issue_date': '2026-08-03',
      'due_date': '2026-08-03',
      'pos_state_code': '27',
      'subtotal': '5000.0000',
      'total': '5900.0000',
      'amount_paid': '0.0000',
      'e_invoice_status': 'PENDING',
      'lines': [],
    });
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(body)),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('save() builds a draft payload with post_on_create=false', () async {
    final adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = adapter;
    final service = InvoiceService(dio);
    final notifier = InvoiceFormNotifier(
      service,
      const InvoiceCalculationService(),
    );

    // Simulate the user filling the form.
    notifier.setContact(
      const Contact(
        id: 'contact-1',
        name: 'Tata Consultancy Services Ltd',
        contactType: ContactType.customer,
        gstin: '27AAACT1234A1Z1',
        stateCode: '27',
      ),
    );
    notifier.setIssueDate(DateTime(2026, 8, 3));
    notifier.setDueDate(DateTime(2026, 9, 2));
    notifier.setPosStateCode('27');
    // The form starts with one empty line; fill it in.
    notifier.updateLineField(0, 'productId', 'product-1');
    notifier.updateLineField(0, 'hsnSac', '84713010');
    notifier.updateLineField(0, 'gstRate', 18);
    notifier.updateLineField(0, 'quantity', 1);
    notifier.updateLineField(0, 'rate', 5000);

    final result = await notifier.save();
    expect(result, isA<Success<dynamic>>());

    final payload = adapter.lastBody!;
    expect(payload['contact_id'], 'contact-1');
    expect(payload['issue_date'], '2026-08-03');
    expect(payload['due_date'], '2026-09-02');
    expect(payload['pos_state_code'], '27');
    expect(payload['is_gst_inclusive'], isFalse);
    expect(payload['is_rcm'], isFalse);
    expect(payload['supply_type'], 'DOMESTIC');
    // Draft save must never auto-post.
    expect(payload['post_on_create'], isFalse);

    final lines = payload['lines'] as List;
    expect(lines.length, 1);
    final line = lines.first as Map<String, dynamic>;
    expect(line['product_id'], 'product-1');
    expect(line['hsn_sac'], '84713010');
    expect(line['gst_rate'], 18);
    expect(line['quantity'], 1);
    expect(line['rate'], 5000);
  });

  test('save() fails validation without a customer', () async {
    final adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = adapter;
    final notifier = InvoiceFormNotifier(
      InvoiceService(dio),
      const InvoiceCalculationService(),
    );

    final result = await notifier.save();
    expect(result, isA<Failure<dynamic>>());
    expect(adapter.lastBody, isNull, reason: 'no request should be sent');
  });
}
