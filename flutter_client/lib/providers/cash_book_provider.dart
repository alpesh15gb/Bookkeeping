import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import '../models/cash_book_model.dart';

class CashBookProvider with ChangeNotifier {
  CashBookResponse? _data;
  bool _isLoading = false;
  String? _error;

  CashBookResponse? get data => _data;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final ApiClient _client = ApiClient();

  Uri _buildUri(String endpoint) {
    final queryParams = <String>[];
    ApiClient.fyParams.forEach((k, v) {
      queryParams.add('$k=$v');
    });
    if (queryParams.isEmpty) return Uri.parse(endpoint);
    final separator = endpoint.contains('?') ? '&' : '?';
    return Uri.parse('$endpoint$separator${queryParams.join('&')}');
  }

  Future<void> fetchCashBook(String startDate, String endDate) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _client.get(
        _buildUri('${ApiClient.baseUrl}/reports/cash-book?start_date=$startDate&end_date=$endDate'),
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        _data = CashBookResponse.fromJson(decoded);
      } else {
        _error = 'Failed to load cash book: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'An error occurred fetching the cash book';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> downloadExcel(String startDate, String endDate) async {
    try {
      final response = await _client.get(
        _buildUri('${ApiClient.baseUrl}/reports/cash-book/excel?start_date=$startDate&end_date=$endDate'),
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> downloadPdf(String startDate, String endDate) async {
    try {
      final response = await _client.get(
        _buildUri('${ApiClient.baseUrl}/reports/cash-book/pdf?start_date=$startDate&end_date=$endDate'),
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}
