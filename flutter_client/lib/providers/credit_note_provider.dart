import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class CreditNoteProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  List<dynamic> _items = [];
  List<dynamic> get items => _items;

  Future<List<dynamic>> fetchCreditNotes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes'));
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

  Future<bool> createCreditNote(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes'),
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

  Future<Map<String, dynamic>?> previewCreditNote(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> finalizeCreditNote(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes/$id/finalize'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to finalize credit note';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> cancelCreditNote(String id) async {
    return _cancel('${ApiClient.baseUrl}/invoices/credit-notes/$id/cancel');
  }

  Future<bool> deleteCreditNote(String id) async {
    return _delete('${ApiClient.baseUrl}/invoices/credit-notes/$id');
  }

  Future<Map<String, dynamic>?> fetchCreditNoteDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/credit-notes/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>> fetchDebitNotes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes'));
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

  Future<bool> createDebitNote(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes'),
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

  Future<Map<String, dynamic>?> previewDebitNote(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> finalizeDebitNote(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes/$id/finalize'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to finalize debit note';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> cancelDebitNote(String id) async {
    return _cancel('${ApiClient.baseUrl}/invoices/debit-notes/$id/cancel');
  }

  Future<bool> deleteDebitNote(String id) async {
    return _delete('${ApiClient.baseUrl}/invoices/debit-notes/$id');
  }

  Future<Map<String, dynamic>?> fetchDebitNoteDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/debit-notes/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchInvoicePdfPayload(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/invoices/$id/pdf-payload'));
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
}
