// InvoiceService tests using a fake HttpClientAdapter.
//
// Verifies that invoice detail/create/list calls use the correct paths and
// that HTTP failures are mapped to the right ApiError categories (404, 401,
// 500) rather than being collapsed into a generic "server unavailable".
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/sales/services/invoice_service.dart';

/// Minimal [HttpClientAdapter] that returns canned JSON/status per request.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(int status, Object data) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Dio _dio(_FakeAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = adapter;

Map<String, dynamic> _decodeBody(RequestOptions options) {
  final data = options.data;
  if (data is String) {
    return jsonDecode(data) as Map<String, dynamic>;
  }
  if (data is Map) {
    return data.cast<String, dynamic>();
  }
  return <String, dynamic>{};
}

void main() {
  group('InvoiceService.get', () {
    test(
      'GET /invoices/{id} parses detail and preserves contact name',
      () async {
        final dio = _dio(
          _FakeAdapter((options) async {
            expect(options.path, '/invoices/inv-123');
            expect(options.method, 'GET');
            return _jsonBody(200, {
              'id': 'inv-123',
              'invoice_number': 'INV/1',
              'status': 'DRAFT',
              'issue_date': '2026-08-03',
              'due_date': '2026-08-03',
              'pos_state_code': '27',
              'subtotal': '5000.0000',
              'total': '5900.0000',
              'amount_paid': '0.0000',
              'e_invoice_status': 'PENDING',
              'lines': [],
              'contact': {'name': 'Customer One', 'billing_address': null},
            });
          }),
        );
        final service = InvoiceService(dio);
        final result = await service.get('inv-123');
        expect(result, isA<Success<dynamic>>());
        final inv = (result as Success).value;
        expect(inv.id, 'inv-123');
        expect(inv.customerName, 'Customer One');
      },
    );

    test('404 maps to ApiError with statusCode 404', () async {
      final dio = _dio(
        _FakeAdapter((options) async {
          return _jsonBody(404, {
            'detail': 'Invoice not found in this company context.',
            'code': 'HTTP_404',
          });
        }),
      );
      final result = await InvoiceService(dio).get('missing');
      final failure = result as Failure;
      expect(failure.error.statusCode, 404);
      expect(failure.error.isNotFound, isTrue);
      expect(failure.error.isServer, isFalse);
    });

    test('401 maps to ApiError with statusCode 401', () async {
      final dio = _dio(
        _FakeAdapter((options) async {
          return _jsonBody(401, {'detail': 'Not authenticated'});
        }),
      );
      final result = await InvoiceService(dio).get('x');
      final failure = result as Failure;
      expect(failure.error.statusCode, 401);
      expect(failure.error.isUnauthorized, isTrue);
    });

    test(
      '500 maps to standard server-unavailable message, not a 404 label',
      () async {
        final dio = _dio(
          _FakeAdapter((options) async {
            return _jsonBody(500, {'detail': 'internal boom'});
          }),
        );
        final result = await InvoiceService(dio).get('x');
        final failure = result as Failure;
        expect(failure.error.statusCode, 500);
        expect(failure.error.isServer, isTrue);
        expect(failure.error.message, contains('server is unavailable'));
      },
    );

    test('malformed response maps to invalid-response error', () async {
      final dio = _dio(
        _FakeAdapter((options) async {
          return _jsonBody(200, {'unexpected': true});
        }),
      );
      final result = await InvoiceService(dio).get('x');
      final failure = result as Failure;
      expect(failure.error.isInvalidResponse, isTrue);
      expect(failure.error.isNetwork, isFalse);
      expect(failure.error.message, contains('invalid invoice response'));
    });

    test('network failure (no response) maps to network ApiError', () async {
      final dio = _dio(
        _FakeAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'Connection refused',
          );
        }),
      );
      final result = await InvoiceService(dio).get('x');
      final failure = result as Failure;
      expect(failure.error.statusCode, isNull);
      expect(failure.error.isNetwork, isTrue);
    });
  });

  group('InvoiceService.list', () {
    test('GET /invoices parses envelope and total', () async {
      final dio = _dio(
        _FakeAdapter((options) async {
          expect(options.path, '/invoices');
          return _jsonBody(200, {
            'items': [
              {
                'id': 'inv-1',
                'invoice_number': 'INV/1',
                'status': 'DRAFT',
                'issue_date': '2026-08-03',
                'due_date': '2026-08-03',
                'total': '5900.0000',
                'amount_paid': '0.0000',
                'contact_name': 'Customer One',
              },
            ],
            'total': 1,
            'page': 1,
            'limit': 50,
          });
        }),
      );
      final result = await InvoiceService(dio).list();
      expect(result, isA<Success<dynamic>>());
      final value = (result as Success).value;
      expect(value.items.length, 1);
      expect(value.total, 1);
      expect(value.items.first.customerName, 'Customer One');
    });
  });

  group('InvoiceService.create', () {
    test('POST /invoices sends payload and parses created invoice', () async {
      Map<String, dynamic>? sentBody;
      final dio = _dio(
        _FakeAdapter((options) async {
          sentBody = _decodeBody(options);
          expect(options.path, '/invoices');
          expect(options.method, 'POST');
          return _jsonBody(201, {
            'id': 'inv-new',
            'invoice_number': 'INV/1',
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
        }),
      );
      final result = await InvoiceService(
        dio,
      ).create({'contact_id': 'c-1', 'pos_state_code': '27', 'line_items': []});
      expect(result, isA<Success<dynamic>>());
      expect(sentBody!['contact_id'], 'c-1');
      expect((result as Success).value.invoiceNumber, 'INV/1');
    });
  });
}
