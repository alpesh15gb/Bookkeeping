/// Invoice API service — all backend calls.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/utils/formatters.dart';
import '../models/invoice.dart';

class InvoiceService {
  InvoiceService(this._dio);
  final Dio _dio;

  // -- Helpers -------------------------------------------------------------

  Invoice _parseInvoiceResponse(Object? data) {
    final map = data is Map<String, dynamic>
        ? data
        : data is Map
        ? data.cast<String, dynamic>()
        : null;
    if (map == null ||
        !map.containsKey('id') ||
        !map.containsKey('invoice_number') ||
        !map.containsKey('status')) {
      throw const ApiError(
        message: 'The server returned an invalid invoice response.',
        type: 'invalid_response',
      );
    }

    try {
      return Invoice.fromJson(map);
    } catch (_) {
      throw const ApiError(
        message: 'The server returned an invalid invoice response.',
        type: 'invalid_response',
      );
    }
  }

  Future<Result<Invoice>> _get(String path) {
    return guardDio(() async {
      final data = (await _dio.get(path)).data;
      return _parseInvoiceResponse(data);
    });
  }

  Future<Result<Invoice>> _post(String path, [Map<String, dynamic>? body]) {
    return guardDio(() async {
      final data = (await _dio.post(path, data: body)).data;
      return _parseInvoiceResponse(data);
    });
  }

  Future<Result<Invoice>> _put(String path, Map<String, dynamic> body) {
    return guardDio(() async {
      final data = (await _dio.put(path, data: body)).data;
      return _parseInvoiceResponse(data);
    });
  }

  // -- CRUD ----------------------------------------------------------------

  Future<Result<Invoice>> create(Map<String, dynamic> payload) =>
      _post('/invoices', payload);

  Future<Result<Invoice>> update(String id, Map<String, dynamic> payload) =>
      _put('/invoices/$id', payload);

  Future<Result<void>> delete(String id) {
    return guardDio(() async {
      await _dio.delete('/invoices/$id');
    });
  }

  Future<Result<Invoice>> get(String id) => _get('/invoices/$id');

  Future<Result<({List<InvoiceListItem> items, int total})>> list({
    int page = 1,
    int limit = 50,
    String? search,
    String? status,
    String? contactId,
    String? dateFrom,
    String? dateTo,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        'search': ?search,
        'status': ?status,
        'contact_id': ?contactId,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
      };
      final res = await _dio.get('/invoices', queryParameters: q);
      final data = res.data is Map
          ? (res.data as Map<String, dynamic>)
          : <String, dynamic>{};
      final rawItems = data['items'];
      final items = (rawItems is List ? rawItems : <dynamic>[])
          .map(
            (e) => InvoiceListItem.fromJson(
              e is Map<String, dynamic> ? e : <String, dynamic>{},
            ),
          )
          .toList();
      return (
        items: items,
        total: parseIntSafe(data['total'], defaultValue: items.length),
      );
    });
  }

  // -- Workflow actions ----------------------------------------------------

  Future<Result<Invoice>> finalize(String id) =>
      _post('/invoices/$id/finalize');
  Future<Result<Invoice>> cancel(String id) => _post('/invoices/$id/cancel');
  Future<Result<Invoice>> clone(String id) => _post('/invoices/$id/clone');
  Future<Result<Invoice>> preview(Map<String, dynamic> payload) =>
      _post('/invoices/preview', payload);

  Future<Result<Invoice>> recordPayment(
    String id, {
    required String contactId,
    required double amount,
    required String paymentMode,
    String? paymentDate,
    String? paymentNumber,
    String? referenceNumber,
    String? description,
    List<Map<String, dynamic>>? allocations,
  }) => _post('/invoices/$id/payment', {
    'contact_id': contactId,
    'payment_mode': paymentMode,
    'payment_date':
        paymentDate ?? DateTime.now().toIso8601String().split('T').first,
    'amount': amount,
    'payment_number': ?paymentNumber,
    'reference_number': ?referenceNumber,
    'description': ?description,
    'allocations': allocations ?? [],
  });

  Future<Result<void>> email(String id, {String? recipientEmail}) {
    return guardDio(() async {
      await _dio.post(
        '/invoices/$id/email',
        data: recipientEmail != null
            ? {'recipient_email': recipientEmail}
            : null,
      );
    });
  }

  /// Returns the /print path for downloading PDF from the backend.
  String getPdfUrl(String id) => '/invoices/$id/print';
}

final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  return InvoiceService(ref.watch(apiClientProvider));
});
