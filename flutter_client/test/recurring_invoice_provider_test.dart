import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/providers/recurring_invoice_provider.dart';
import 'mock_api_client/mock_api_client.dart';

void main() {
  test('createRecurringInvoice sends end_date for ON_DATE templates', () async {
    Map<String, dynamic>? capturedPayload;
    final client = MockApiClient(
      responder: (request) async {
        if (request is http.Request) {
          capturedPayload = jsonDecode(request.body) as Map<String, dynamic>;
        }
        return http.Response('{}', 201);
      },
    );
    final provider = RecurringInvoiceProvider(client: client);

    final success = await provider.createRecurringInvoice({
      'contact_id': 'contact-1',
      'template_name': 'Monthly AMC',
      'frequency': 'MONTHLY',
      'interval_count': 1,
      'next_date': '2026-07-01',
      'end_mode': 'ON_DATE',
      'end_date': '2027-03-31',
      'max_occurrences': null,
      'pos_state_code': '27',
      'items': const [],
    });

    expect(success, isTrue);
    expect(capturedPayload?['end_mode'], 'ON_DATE');
    expect(capturedPayload?['end_date'], '2027-03-31');
    expect(capturedPayload?['max_occurrences'], isNull);
  });

  test('createRecurringInvoice sends max_occurrences for AFTER_N templates', () async {
    Map<String, dynamic>? capturedPayload;
    final client = MockApiClient(
      responder: (request) async {
        if (request is http.Request) {
          capturedPayload = jsonDecode(request.body) as Map<String, dynamic>;
        }
        return http.Response('{}', 201);
      },
    );
    final provider = RecurringInvoiceProvider(client: client);

    final success = await provider.createRecurringInvoice({
      'contact_id': 'contact-1',
      'template_name': 'Quarterly Subscription',
      'frequency': 'QUARTERLY',
      'interval_count': 1,
      'next_date': '2026-07-01',
      'end_mode': 'AFTER_N',
      'end_date': null,
      'max_occurrences': 6,
      'pos_state_code': '27',
      'items': const [],
    });

    expect(success, isTrue);
    expect(capturedPayload?['end_mode'], 'AFTER_N');
    expect(capturedPayload?['end_date'], isNull);
    expect(capturedPayload?['max_occurrences'], 6);
  });
}
