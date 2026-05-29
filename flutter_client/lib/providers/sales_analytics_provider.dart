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

  Future<void> fetchCustomerWise() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales/customer-wise'));
      if (response.statusCode == 200) {
        _customerWise = jsonDecode(response.body) as List;
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
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales/period-wise'));
      if (response.statusCode == 200) {
        _periodWise = jsonDecode(response.body) as List;
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
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales/transactions'));
      if (response.statusCode == 200) {
        _transactions = jsonDecode(response.body) as List;
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
        _client.get(Uri.parse('${ApiClient.baseUrl}/sales/customer-wise')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/sales/period-wise')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/sales/transactions')),
      ]);

      for (int i = 0; i < results.length; i++) {
        if (results[i].statusCode != 200) {
          _errorMessage = 'Failed to load sales analytics';
          _isLoading = false;
          notifyListeners();
          return;
        }
      }

      _customerWise = jsonDecode(results[0].body) as List;
      _periodWise = jsonDecode(results[1].body) as List;
      _transactions = jsonDecode(results[2].body) as List;
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }
}
