import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/recurring_invoice.dart';
import 'package:http/http.dart' as http;

class RecurringInvoiceProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final http.Client _client;

  RecurringInvoiceProvider({http.Client? client}) : _client = client ?? ApiClient();

  Uri _buildUri(String endpoint) {
    final queryParams = <String>[];
    ApiClient.fyParams.forEach((k, v) {
      queryParams.add('$k=$v');
    });
    if (queryParams.isEmpty) return Uri.parse(endpoint);
    final separator = endpoint.contains('?') ? '&' : '?';
    return Uri.parse('$endpoint$separator${queryParams.join('&')}');
  }

  List<RecurringInvoiceModel> _items = [];
  List<RecurringInvoiceModel> get items => _items;

  Future<List<RecurringInvoiceModel>> fetchRecurringInvoices({bool activeOnly = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final url = activeOnly
          ? '${ApiClient.baseUrl}/recurring-invoices?active_only=true'
          : '${ApiClient.baseUrl}/recurring-invoices';
      final response = await _client.get(_buildUri(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data is List ? data : [];
        _items = list.map((e) => RecurringInvoiceModel.fromJson(e)).toList();
        _isLoading = false;
        notifyListeners();
        return _items;
      }
      _errorMessage = 'Failed to load recurring invoices';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<RecurringInvoiceModel?> fetchRecurringInvoiceDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/recurring-invoices/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return RecurringInvoiceModel.fromJson(data);
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    return null;
  }

  Future<bool> createRecurringInvoice(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/recurring-invoices'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateRecurringInvoice(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        _buildUri('${ApiClient.baseUrl}/recurring-invoices/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteRecurringInvoice(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(
        Uri.parse('${ApiClient.baseUrl}/recurring-invoices/$id'),
      );
      if (response.statusCode == 204 || response.statusCode == 200) {
        _items.removeWhere((e) => e.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to delete';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<Map<String, dynamic>?> generateInvoice(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/recurring-invoices/$id/generate'),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to generate invoice';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return null;
  }
}
