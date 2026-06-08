import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/local_database.dart';
import 'package:flutter_client/core/sync_manager.dart';
import 'package:flutter_client/models/invoice.dart';

class InvoiceProvider extends ChangeNotifier {
  List<InvoiceModel> _invoices = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  static const int _pageSize = 50;

  List<InvoiceModel> get invoices => _invoices;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;

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

  Future<void> fetchInvoices({String? search, String? status, bool reset = true}) async {
    if (reset) {
      _currentPage = 1;
      _invoices = [];
      _hasMore = true;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final queryParams = <String>['page=$_currentPage', 'limit=$_pageSize'];
      if (search != null && search.isNotEmpty) {
        queryParams.add('search=${Uri.encodeComponent(search)}');
      }
      if (status != null && status != 'ALL') {
        queryParams.add('status=$status');
      }
      final queryString = '?${queryParams.join('&')}';
      
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/invoices$queryString'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data is Map ? (data['items'] ?? []) : data;
        final newInvoices = items
            .whereType<Map<String, dynamic>>()
            .map((x) => InvoiceModel.fromJson(x))
            .toList();
        if (reset) {
          _invoices = newInvoices;
        } else {
          _invoices.addAll(newInvoices);
        }
        _totalPages = ((data['total'] ?? 0) / _pageSize).ceil();
        _hasMore = _currentPage < _totalPages;
        await SyncManager.instance?.cacheGetResponse('/invoices', items);
      } else {
        _errorMessage = 'Failed to load invoices';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    }
    if (_invoices.isEmpty && !(SyncManager.instance?.isOnline ?? true)) {
      try {
        final cached = await LocalDatabase.query(
          'cached_invoices',
          where: 'tenant_id = ?',
          whereArgs: [ApiClient.tenantId],
        );
        _invoices = cached.map((row) {
          final jsonStr = row['json'] as String?;
          return InvoiceModel.fromJson(jsonStr != null ? jsonDecode(jsonStr) : row);
        }).toList();
        // Check cache staleness
        if (cached.isNotEmpty) {
          final syncedAt = cached.first['synced_at'] as String?;
          if (syncedAt != null) {
            final syncTime = DateTime.tryParse(syncedAt);
            if (syncTime != null && DateTime.now().difference(syncTime).inHours > 24) {
              _errorMessage = 'Cached data is over 24 hours old. Connect to refresh.';
            } else {
              _errorMessage = _invoices.isNotEmpty ? null : 'No cached invoices available';
            }
          } else {
            _errorMessage = _invoices.isNotEmpty ? null : 'No cached invoices available';
          }
        } else {
          _errorMessage = 'No cached invoices available';
        }
      } catch (_) {}
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreInvoices({String? search, String? status}) async {
    if (!_hasMore || _isLoading) return;
    _currentPage++;
    await fetchInvoices(search: search, status: status, reset: false);
  }

  Future<InvoiceModel?> previewInvoice(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/invoices/preview'),
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
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'create_invoice',
        endpoint: '${ApiClient.baseUrl}/invoices',
        method: 'POST',
        body: body,
      );
      if (queued) {
        // Optimistic UI: add placeholder to local list
        final placeholder = {
          'id': 'pending-${DateTime.now().millisecondsSinceEpoch}',
          'invoice_number': payload['invoice_number'] ?? 'Pending',
          'issue_date': payload['issue_date']?.toString() ?? '',
          'status': 'DRAFT',
          'total': 0.0,
          'amount_paid': 0.0,
          'contact_name': '',
        };
        _invoices.insert(0, placeholder);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/invoices'),
        body: body,
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
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/invoices/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await SyncManager.instance?.cacheDocumentDetail('/invoices/$id', data);
        return InvoiceModel.fromJson(data);
      } else {
        debugPrint('fetchInvoiceDetail server returned error: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stack) {
      debugPrint('fetchInvoiceDetail error: $e');
      debugPrint('Stacktrace: $stack');
    }
    if (!(SyncManager.instance?.isOnline ?? true)) {
      final cached = await LocalDatabase.getCachedDocumentDetail(
        ApiClient.tenantId ?? '', 'invoice', id,
      );
      if (cached != null) return InvoiceModel.fromJson(cached);
    }
    return null;
  }

  Future<bool> updateInvoice(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'update_invoice',
        endpoint: '${ApiClient.baseUrl}/invoices/$id',
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
        _buildUri('${ApiClient.baseUrl}/invoices/$id'),
        body: body,
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
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'cancel_invoice',
        endpoint: '${ApiClient.baseUrl}/invoices/$id/cancel',
        method: 'POST',
      );
      if (queued) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/invoices/$id/cancel'),
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
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'finalize_invoice',
        endpoint: '${ApiClient.baseUrl}/invoices/$id/finalize',
        method: 'POST',
      );
      if (queued) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/invoices/$id/finalize'),
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
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'record_payment',
        endpoint: '${ApiClient.baseUrl}/invoices/$id/payment',
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
        _buildUri('${ApiClient.baseUrl}/invoices/$id/payment'),
        body: body,
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
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'delete_invoice',
        endpoint: '${ApiClient.baseUrl}/invoices/$id',
        method: 'DELETE',
      );
      if (queued) {
        _invoices.removeWhere((inv) => inv.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.delete(
        _buildUri('${ApiClient.baseUrl}/invoices/$id'),
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
