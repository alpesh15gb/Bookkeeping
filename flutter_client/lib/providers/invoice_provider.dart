import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/invoice.dart';

class InvoiceProvider extends ChangeNotifier {
  List<InvoiceModel> _invoices = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<InvoiceModel> get invoices => _invoices;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  Future<void> fetchInvoices({String? search, String? status}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final queryParams = <String>[];
      if (search != null && search.isNotEmpty) {
        queryParams.add('search=${Uri.encodeComponent(search)}');
      }
      if (status != null && status != 'ALL') {
        queryParams.add('status=$status');
      }
      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices$queryString'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List items = data['items'] ?? [];
        // Note: list response fields might be minimal, so we convert them to full Models with fallback values.
        _invoices = items.map((x) => InvoiceModel.fromJson(x)).toList();
      } else {
        _errorMessage = 'Failed to load invoices';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<InvoiceModel?> previewInvoice(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return InvoiceModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> createInvoice(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchInvoices();
        return true;
      } else {
        _errorMessage = ApiClient.parseError(response.body, fallback: 'Failed to create invoice');
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<InvoiceModel?> fetchInvoiceDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/$id'));
      if (response.statusCode == 200) {
        return InvoiceModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateInvoice(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/invoices/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchInvoices();
        return true;
      } else {
        _errorMessage = ApiClient.parseError(response.body, fallback: 'Failed to update invoice');
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> cancelInvoice(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/$id/cancel'),
      );
      if (response.statusCode == 200) {
        await fetchInvoices();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to cancel invoice';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> finalizeInvoice(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/$id/finalize'),
      );
      if (response.statusCode == 200) {
        await fetchInvoices();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to finalize invoice';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> recordPayment(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/$id/payment'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchInvoices();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to record payment';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> deleteInvoice(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.delete(
        Uri.parse('${ApiClient.baseUrl}/invoices/$id'),
      );
      if (response.statusCode == 204 || response.statusCode == 200) {
        await fetchInvoices();
        return true;
      } else {
        _errorMessage = ApiClient.parseError(response.body, fallback: 'Failed to delete invoice');
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }
}
