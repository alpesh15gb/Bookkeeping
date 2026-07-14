/// Payment API service — all backend calls for receipts (AR).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/payment_models.dart';
import '../models/outstanding_invoice.dart';

class PaymentService {
  PaymentService(this._dio);
  final Dio _dio;

  Future<Result<Payment>> create(Map<String, dynamic> payload) {
    return guardDio(() async {
      return Payment.fromJson(
        (await _dio.post('/payments/receipts', data: payload)).data
            as Map<String, dynamic>,
      );
    });
  }

  Future<Result<List<PaymentListItem>>> list({
    int page = 1,
    int limit = 50,
    String? contactId,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{
        'page': page,
        'limit': limit,
        if (contactId != null) 'contact_id': contactId,
      };
      final res = await _dio.get('/payments/receipts', queryParameters: q);
      return (res.data as List)
          .map((e) => PaymentListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<Payment>> get(String id) {
    return guardDio(() async {
      return Payment.fromJson(
        (await _dio.get('/payments/receipts/$id')).data as Map<String, dynamic>,
      );
    });
  }

  Future<Result<List<OutstandingInvoice>>> outstanding(String contactId) {
    return guardDio(() async {
      final res = await _dio.get('/payments/receipts/outstanding/$contactId');
      return (res.data as List)
          .map(
            (e) =>
                OutstandingInvoice.fromInvoiceJson(e as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<Result<Payment>> cancel(String id, {required String reason}) {
    return guardDio(() async {
      return Payment.fromJson(
        (await _dio.post(
              '/payments/receipts/$id/cancel',
              data: {'reason': reason},
            )).data
            as Map<String, dynamic>,
      );
    });
  }
}

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(apiClientProvider));
});
