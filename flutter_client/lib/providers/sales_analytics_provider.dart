import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class SalesAnalyticsProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _customerWise = [];
  List<dynamic> _periodWise = [];
  List<dynamic> _transactions = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<dynamic> get customerWise => _customerWise;
  List<dynamic> get periodWise => _periodWise;
  List<dynamic> get transactions => _transactions;

  final ApiClient _client = ApiClient();

  Uri _buildUri(String endpoint) {
    final queryParams = <String>[];
    ApiClient.fyParams.forEach((k, v) {
      queryParams.add('$k=$v');
    });
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    return Uri.parse('$endpoint$queryString');
  }

  Future<void> fetchCustomerWise() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/sales/customer-wise'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _customerWise = data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      } else {
        _errorMessage = 'Failed to load customer-wise sales';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchPeriodWise() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/sales/period-wise'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _periodWise = data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      } else {
        _errorMessage = 'Failed to load period-wise sales';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchTransactions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/sales/transactions'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _transactions = data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      } else {
        _errorMessage = 'Failed to load sales transactions';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _client.get(_buildUri('${ApiClient.baseUrl}/sales/customer-wise')),
        _client.get(_buildUri('${ApiClient.baseUrl}/sales/period-wise')),
        _client.get(_buildUri('${ApiClient.baseUrl}/sales/transactions')),
      ]);

      for (int i = 0; i < results.length; i++) {
        if (results[i].statusCode != 200) {
          _errorMessage = 'Failed to load sales analytics';
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      final cw = jsonDecode(results[0].body);
      _customerWise = cw is List ? cw : (cw is Map ? (cw['items'] ?? []) : []);
      final pw = jsonDecode(results[1].body);
      _periodWise = pw is List ? pw : (pw is Map ? (pw['items'] ?? []) : []);
      final tx = jsonDecode(results[2].body);
      _transactions = tx is List ? tx : (tx is Map ? (tx['items'] ?? []) : []);
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }
}
