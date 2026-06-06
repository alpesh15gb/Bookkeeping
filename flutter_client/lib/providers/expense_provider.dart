import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/local_database.dart';
import 'package:flutter_client/core/sync_manager.dart';

class ExpenseProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  List<dynamic> _items = [];
  List<dynamic> get items => _items;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  static const int _pageSize = 50;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalItems => _totalItems;

  List<dynamic> _expenseCategories = [];
  List<dynamic> get expenseCategories => _expenseCategories;
  List<dynamic> _taxTemplates = [];
  List<dynamic> get taxTemplates => _taxTemplates;
  List<dynamic> _paymentTerms = [];
  List<dynamic> get paymentTerms => _paymentTerms;

  Uri _buildUri(String endpoint) {
    final queryParams = <String>[];
    ApiClient.fyParams.forEach((k, v) {
      queryParams.add('$k=$v');
    });
    if (queryParams.isEmpty) return Uri.parse(endpoint);
    final separator = endpoint.contains('?') ? '&' : '?';
    return Uri.parse('$endpoint$separator${queryParams.join('&')}');
  }

  Future<List<dynamic>> fetchExpenses({int page = 1}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/expenses?page=$page&limit=$_pageSize'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          _items = data['items'] ?? data['data'] ?? [];
          _totalPages = data['total_pages'] ?? data['pages'] ?? 1;
          _totalItems = data['total'] ?? data['count'] ?? _items.length;
        } else {
          _items = data;
          _totalPages = 1;
          _totalItems = _items.length;
        }
        _currentPage = page;
        await SyncManager.instance?.cacheGetResponse('/expenses', _items);
      }
    } catch (_) {
      _errorMessage = 'Failed to load expenses';
    }
    if (_items.isEmpty && !(SyncManager.instance?.isOnline ?? true)) {
      try {
        final cached = await LocalDatabase.query(
          'cached_expenses',
          where: 'tenant_id = ?',
          whereArgs: [ApiClient.tenantId],
        );
        _items = cached.map((row) {
          final jsonStr = row['json'] as String?;
          return jsonStr != null ? jsonDecode(jsonStr) : row;
        }).toList();
        _totalItems = _items.length;
        _totalPages = 1;
        _errorMessage = _items.isNotEmpty ? null : 'No cached expenses available';
      } catch (_) {}
    }
    _isLoading = false;
    notifyListeners();
    return _items;
  }

  void nextPage() {
    if (_currentPage < _totalPages) fetchExpenses(page: _currentPage + 1);
  }

  void previousPage() {
    if (_currentPage > 1) fetchExpenses(page: _currentPage - 1);
  }

  Future<bool> createExpense(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'create_expense',
        endpoint: '${ApiClient.baseUrl}/expenses',
        method: 'POST',
        body: body,
      );
      if (queued) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/expenses'),
        body: body,
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

  Future<bool> updateExpense(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'update_expense',
        endpoint: '${ApiClient.baseUrl}/expenses/$id',
        method: 'PUT',
        body: body,
      );
      if (queued) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.put(
        _buildUri('${ApiClient.baseUrl}/expenses/$id'),
        body: body,
      );
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update expense';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteExpense(String id) async {
    return _delete('${ApiClient.baseUrl}/expenses/$id');
  }

  Future<bool> postExpense(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'post_expense',
        endpoint: '${ApiClient.baseUrl}/expenses/$id/post',
        method: 'POST',
      );
      if (queued) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(_buildUri('${ApiClient.baseUrl}/expenses/$id/post'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to post expense';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> cancelExpense(String id) async {
    return _cancel('${ApiClient.baseUrl}/expenses/$id/cancel');
  }

  Future<Map<String, dynamic>?> fetchExpenseDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/expenses/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final safeData = data is Map<String, dynamic> ? data : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
        await SyncManager.instance?.cacheDocumentDetail('/expenses/$id', safeData);
        return safeData;
      }
    } catch (_) {}
    if (!(SyncManager.instance?.isOnline ?? true)) {
      final cached = await LocalDatabase.getCachedDocumentDetail(
        ApiClient.tenantId ?? '', 'expense', id,
      );
      if (cached != null) return cached;
    }
    return null;
  }

  Future<void> fetchExpenseCategories() async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/masters/expense-categories'));
      if (response.statusCode == 200) {
        _expenseCategories = jsonDecode(response.body);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> createExpenseCategory(String name) async {
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/masters/expense-categories'),
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 201) {
        await fetchExpenseCategories();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> previewExpense(double amount, double gstRate) async {
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/expenses/preview'),
        body: jsonEncode({
          'amount': amount,
          'gst_rate': gstRate,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : (data is Map ? Map<String, dynamic>.from(data) : null);
      }
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>> fetchTaxTemplates() async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/masters/tax-templates'));
      if (response.statusCode == 200) {
        _taxTemplates = jsonDecode(response.body);
        notifyListeners();
        return _taxTemplates;
      }
    } catch (_) {}
    return _taxTemplates;
  }

  Future<List<dynamic>> fetchPaymentTerms() async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/masters/payment-terms'));
      if (response.statusCode == 200) {
        _paymentTerms = jsonDecode(response.body);
        notifyListeners();
        return _paymentTerms;
      }
    } catch (_) {}
    return _paymentTerms;
  }

  Future<Map<String, dynamic>?> fetchBillPdfPayload(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bills/$id/pdf-payload'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : (data is Map ? Map<String, dynamic>.from(data) : null);
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> exportGstr1() async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/gst/gstr1/export'));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> exportGstr2() async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/gst/gstr2/export'));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> exportGstr3b() async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/gst/gstr3b/export'));
      if (response.statusCode == 200) return response.bodyBytes;
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
    final id = url.split('/').last;
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'delete_expense',
        endpoint: url,
        method: 'DELETE',
      );
      if (queued) {
        _items.removeWhere((e) => (e['id']?.toString()) == id);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
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
