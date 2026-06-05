import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class BankReconciliationProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _statements = [];
  List<dynamic> _reconciliations = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<dynamic> get statements => _statements;
  List<dynamic> get reconciliations => _reconciliations;

  final ApiClient _client = ApiClient();

  Uri _buildUri(String endpoint) {
    final queryParams = <String>[];
    ApiClient.fyParams.forEach((k, v) {
      queryParams.add('$k=$v');
    });
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    return Uri.parse('$endpoint$queryString');
  }

  Future<void> fetchStatements() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bank-reconciliation/statements'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _statements = data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      } else {
        _errorMessage = 'Failed to load statements (${response.statusCode})';
      }
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> fetchStatementDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bank-reconciliation/statements/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : (data is Map ? Map<String, dynamic>.from(data) : null);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> uploadStatement(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/bank-reconciliation/statements'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchStatements();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Upload failed (${response.statusCode})';
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<List<dynamic>> fetchStatementTransactions(String statementId) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bank-reconciliation/statements/$statementId/transactions'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      }
    } catch (_) {}
    return [];
  }

  Future<bool> addTransaction(String statementId, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/bank-reconciliation/statements/$statementId/transactions'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false; notifyListeners(); return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed';
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false; notifyListeners();
    return false;
  }

  Future<bool> reconcileTransaction(String transactionId, Map<String, dynamic> payload) async {
    _isLoading = true; _errorMessage = null; notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/bank-reconciliation/transactions/$transactionId/reconcile'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 201) { _isLoading = false; notifyListeners(); return true; }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Reconcile failed';
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false; notifyListeners();
    return false;
  }

  Future<void> fetchReconciliations() async {
    _isLoading = true; _errorMessage = null; notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bank-reconciliation/reconciliations'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _reconciliations = data is List ? data : (data is Map ? (data['items'] ?? []) : []);
      } else {
        _errorMessage = 'Failed (${response.statusCode})';
      }
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false; notifyListeners();
  }

  Future<Map<String, dynamic>?> fetchReconciliationDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bank-reconciliation/reconciliations/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : (data is Map ? Map<String, dynamic>.from(data) : null);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> undoReconciliation(String id) async {
    _isLoading = true; _errorMessage = null; notifyListeners();
    try {
      final response = await _client.post(_buildUri('${ApiClient.baseUrl}/bank-reconciliation/reconciliations/$id/undo'));
      if (response.statusCode == 200) {
        await fetchReconciliations(); return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Undo failed';
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false; notifyListeners();
    return false;
  }
}
