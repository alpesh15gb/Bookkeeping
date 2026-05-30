import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class PurchaseOrderProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  List<dynamic> _items = [];
  List<dynamic> get items => _items;

  Future<List<dynamic>> fetchPurchaseOrders() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/purchase-orders'));
      if (response.statusCode == 200) {
        _items = jsonDecode(response.body);
        _isLoading = false;
        notifyListeners();
        return _items;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createPurchaseOrder(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/purchase-orders'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updatePurchaseOrder(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/purchase-orders/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update purchase order';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> finalizePurchaseOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/purchase-orders/$id/finalize');
  }

  Future<bool> cancelPurchaseOrder(String id) async {
    return _cancel('${ApiClient.baseUrl}/purchase-orders/$id/cancel');
  }

  Future<bool> confirmPurchaseOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/purchase-orders/$id/confirm');
  }

  Future<bool> receivePurchaseOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/purchase-orders/$id/receive');
  }

  Future<bool> deletePurchaseOrder(String id) async {
    return cancelPurchaseOrder(id);
  }

  Future<Map<String, dynamic>?> fetchPurchaseOrderDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/purchase-orders/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchPurchaseOrderPdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/purchase-orders/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>> fetchSalesOrders() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales-orders'));
      if (response.statusCode == 200) {
        _items = jsonDecode(response.body);
        _isLoading = false;
        notifyListeners();
        return _items;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createSalesOrder(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/sales-orders'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateSalesOrder(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/sales-orders/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update sales order';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> finalizeSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/finalize');
  }

  Future<bool> cancelSalesOrder(String id) async {
    return _cancel('${ApiClient.baseUrl}/sales-orders/$id/cancel');
  }

  Future<bool> convertSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/convert');
  }

  Future<bool> confirmSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/confirm');
  }

  Future<bool> deliverSalesOrder(String id) async {
    return _postAction('${ApiClient.baseUrl}/sales-orders/$id/deliver');
  }

  Future<bool> deleteSalesOrder(String id) async {
    return cancelSalesOrder(id);
  }

  Future<Map<String, dynamic>?> fetchSalesOrderDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales-orders/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchSalesOrderPdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/sales-orders/$id/pdf-payload'));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<bool> _cancel(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse(url));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Cancel failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> _delete(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(Uri.parse(url));
      if (response.statusCode == 204) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Delete failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> _postAction(String url) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse(url));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Action failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }
}
