/// GST compliance API service — connects to /gst/* and /reports/gst/* endpoints.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/gst_models.dart';

class GstService {
  GstService(this._dio);
  final Dio _dio;

  /// Fetches GSTR-1 outward supply detail from /gst/gstr1.
  Future<Result<Gstr1Summary>> getGstr1({String? startDate, String? endDate}) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (startDate != null) q['start_date'] = startDate;
      if (endDate != null) q['end_date'] = endDate;
      final res = await _dio.get('/gst/gstr1', queryParameters: q);
      return Gstr1Summary.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Book-side inward supplies used to reconcile against portal GSTR-2B.
  Future<Result<Gstr2Summary>> getGstr2({String? startDate, String? endDate}) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (startDate != null) q['start_date'] = startDate;
      if (endDate != null) q['end_date'] = endDate;
      final res = await _dio.get('/gst/gstr2', queryParameters: q);
      return Gstr2Summary.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Fetches GSTR-3B monthly summary from /reports/gst/gstr3b.
  /// Both dates are required.
  Future<Result<Gstr3BSummary>> getGstr3b({
    required String startDate,
    required String endDate,
  }) {
    return guardDio(() async {
      final res = await _dio.get(
        '/reports/gst/gstr3b',
        queryParameters: {'start_date': startDate, 'end_date': endDate},
      );
      return Gstr3BSummary.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Lists GST return tracking records from /gst/returns.
  Future<Result<List<GstReturn>>> listReturns({
    String? returnType,
    String? status,
  }) {
    return guardDio(() async {
      final q = <String, dynamic>{};
      if (returnType != null) q['return_type'] = returnType;
      if (status != null) q['status'] = status;
      final res = await _dio.get('/gst/returns', queryParameters: q);
      final list = (res.data as List?) ?? [];
      return list
          .map((e) => GstReturn.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Creates a new GST return tracking record.
  Future<Result<GstReturn>> createReturn({
    required String returnType,
    required String periodStart,
    required String periodEnd,
    String status = 'DRAFT',
    String? arn,
  }) {
    return guardDio(() async {
      final body = <String, dynamic>{
        'return_type': returnType,
        'period_start': periodStart,
        'period_end': periodEnd,
        'status': status,
      };
      if (arn != null) body['arn'] = arn;
      final res = await _dio.post('/gst/returns', data: body);
      return GstReturn.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Updates an existing GST return tracking record.
  Future<Result<GstReturn>> updateReturn({
    required String id,
    required String status,
    String? arn,
    String? filedAt,
  }) {
    return guardDio(() async {
      final body = <String, dynamic>{'status': status};
      if (arn != null) body['arn'] = arn;
      if (filedAt != null) body['filed_at'] = filedAt;
      final res = await _dio.put('/gst/returns/$id', data: body);
      return GstReturn.fromJson(res.data as Map<String, dynamic>);
    });
  }
}

final gstServiceProvider = Provider<GstService>((ref) {
  return GstService(ref.watch(apiClientProvider));
});
