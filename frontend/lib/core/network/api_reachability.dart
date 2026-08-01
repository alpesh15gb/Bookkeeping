library;

import 'dart:async';

import 'package:dio/dio.dart';

/// Tests reachability of the actual API, not merely the presence of a network
/// interface (which can be a captive portal or an offline LAN).
class ApiReachabilityService {
  ApiReachabilityService(this._dio);

  final Dio _dio;
  final _controller = StreamController<bool>.broadcast();
  bool _lastReachable = false;

  Stream<bool> get changes => _controller.stream;
  bool get lastReachable => _lastReachable;

  Future<bool> probe() async {
    var reachable = false;
    try {
      final response = await _dio.get<Object>(
        '/health',
        options: Options(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      reachable =
          response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } on DioException {
      reachable = false;
    }
    _lastReachable = reachable;
    if (!_controller.isClosed) _controller.add(reachable);
    return reachable;
  }

  Future<void> dispose() => _controller.close();
}
