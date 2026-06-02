import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  static const Duration _requestTimeout = Duration(seconds: 30);

  // Default API URL pointing to the running backend
  static String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.apexbooks.in/api/v1',
  );

  static String parseError(
    String responseBody, {
    String fallback = 'An error occurred',
  }) {
    try {
      final data = jsonDecode(responseBody);
      final detail = data['detail'];
      if (detail == null) return fallback;
      if (detail is String) return detail;
      if (detail is List) {
        final messages = detail
            .map((e) {
              if (e is Map) {
                final loc = e['loc'] is List ? (e['loc'] as List).last : '';
                final msg = e['msg'] ?? '';
                return loc.isNotEmpty ? '$loc: $msg' : '$msg';
              }
              return e.toString();
            })
            .join(', ');
        return messages.isNotEmpty ? messages : fallback;
      }
    } catch (_) {}
    return fallback;
  }

  static String? _accessToken;
  static String? _refreshToken;
  static String? _tenantId;
  static Function()? onSessionExpired;
  static Completer<bool>? _refreshCompleter;

  static void setAccessToken(String? token) {
    _accessToken = token;
  }

  static void setTenantId(String? tenantId) {
    _tenantId = tenantId;
    SharedPreferences.getInstance().then((prefs) {
      if (tenantId != null) {
        prefs.setString('active_tenant_id', tenantId);
      } else {
        prefs.remove('active_tenant_id');
      }
    });
  }

  static String? get tenantId => _tenantId;
  static String? get accessToken => _accessToken;
  static bool get hasSavedSession => _refreshToken != null;

  static Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    _refreshToken = prefs.getString('_rt');
    _tenantId = prefs.getString('active_tenant_id');
  }

  static Future<void> saveRefreshToken(String? token) async {
    _refreshToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString('_rt', token);
    } else {
      await prefs.remove('_rt');
    }
  }

  static Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _tenantId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_rt');
    await prefs.remove('active_tenant_id');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Inject Headers
    if (request is! http.MultipartRequest) {
      request.headers['Content-Type'] = 'application/json';
    }
    request.headers['Accept-Encoding'] = 'gzip';
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }
    if (_tenantId != null) {
      request.headers['X-Tenant-ID'] = _tenantId!;
    }

    if (kDebugMode) {
      debugPrint('HTTP [${request.method}] -> ${request.url}');
    }

    // 2. Send Request with timeout
    http.StreamedResponse response;
    try {
      response = await _inner.send(request).timeout(_requestTimeout);
    } catch (e) {
      // Network failure — return synthetic error response
      final fakeBody = jsonEncode({
        'detail': 'Network error. Please check your connection and try again.',
      });
      final fakeBytes = utf8.encode(fakeBody);
      return http.StreamedResponse(
        Stream.fromIterable([fakeBytes]),
        503,
        contentLength: fakeBytes.length,
        headers: {'content-type': 'application/json'},
      );
    }

    if (kDebugMode) {
      debugPrint('HTTP [${response.statusCode}] <- ${request.url}');
    }

    // 3. Handle 401 Unauthorized (Excluding auth login/register/refresh/logout endpoints)
    final path = request.url.path;
    final isAuthEndpoint =
        path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/logout');

    if (response.statusCode == 401 && !isAuthEndpoint) {
      final hadAccessToken = _accessToken != null;
      if (_accessToken == null && _refreshToken == null) {
        return response;
      }

      bool refreshSucceeded;
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        refreshSucceeded = await _refreshCompleter!.future;
      } else {
        _refreshCompleter = Completer<bool>();
        refreshSucceeded = await _refreshTokenFlow();
        _refreshCompleter!.complete(refreshSucceeded);
        _refreshCompleter = null;
      }

      if (refreshSucceeded) {
        final newRequest = _copyRequest(request);
        newRequest.headers['Authorization'] = 'Bearer $_accessToken';
        if (_tenantId != null) {
          newRequest.headers['X-Tenant-ID'] = _tenantId!;
        }
        return await _inner.send(newRequest).timeout(_requestTimeout);
      } else {
        await clearSession();
        if (hadAccessToken && onSessionExpired != null) {
          onSessionExpired!();
        }
      }
    }

    return response;
  }

  Future<bool> _refreshTokenFlow() async {
    if (_refreshToken == null) return false;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        final newRefreshToken = data['refresh_token'];
        await saveRefreshToken(newRefreshToken);
        return true;
      }
    } catch (_) {}
    return false;
  }

  http.BaseRequest _copyRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..maxRedirects = request.maxRedirects
        ..followRedirects = request.followRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;
      return copy;
    }
    if (request is http.MultipartRequest) {
      final copy = http.MultipartRequest(request.method, request.url)
        ..headers.addAll(request.headers)
        ..maxRedirects = request.maxRedirects
        ..followRedirects = request.followRedirects
        ..persistentConnection = request.persistentConnection
        ..fields.addAll(request.fields);
      for (final file in request.files) {
        copy.files.add(file);
      }
      return copy;
    }
    return request;
  }
}
