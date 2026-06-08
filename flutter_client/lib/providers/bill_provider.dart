import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/local_database.dart';
import 'package:flutter_client/core/sync_manager.dart';
import 'package:flutter_client/models/bill.dart';

class BillProvider extends ChangeNotifier {
  List<BillModel> _bills = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  static const int _pageSize = 50;

  List<BillModel> get bills => _bills;
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

  Future<void> fetchBills({bool reset = true}) async {
    if (reset) {
      _currentPage = 1;
      _bills = [];
      _hasMore = true;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final queryParams = <String>['page=$_currentPage', 'limit=$_pageSize'];
      final queryString = '?${queryParams.join('&')}';
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bills$queryString'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data is Map ? (data['items'] ?? []) : data;
        final newBills = items
            .whereType<Map<String, dynamic>>()
            .map((x) => BillModel.fromJson(x))
            .toList();
        if (reset) {
          _bills = newBills;
        } else {
          _bills.addAll(newBills);
        }
        if (data is Map) {
          _totalPages = ((data['total'] ?? 0) / _pageSize).ceil();
          _hasMore = _currentPage < _totalPages;
        }
        await SyncManager.instance?.cacheGetResponse('/bills', items);
      } else {
        _errorMessage = 'Failed to load vendor bills';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    }
    if (_bills.isEmpty && !(SyncManager.instance?.isOnline ?? true)) {
      try {
        final cached = await LocalDatabase.query(
          'cached_bills',
          where: 'tenant_id = ?',
          whereArgs: [ApiClient.tenantId],
        );
        _bills = cached.map((row) {
          final jsonStr = row['json'] as String?;
          return BillModel.fromJson(jsonStr != null ? jsonDecode(jsonStr) : row);
        }).toList();
        _errorMessage = _bills.isNotEmpty ? null : 'No cached bills available';
      } catch (_) {}
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreBills() async {
    if (!_hasMore || _isLoading) return;
    _currentPage++;
    await fetchBills(reset: false);
  }

  Future<BillModel?> fetchBillDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/bills/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await SyncManager.instance?.cacheDocumentDetail('/bills/$id', data);
        return BillModel.fromJson(data);
      }
    } catch (_) {}
    if (!(SyncManager.instance?.isOnline ?? true)) {
      final cached = await LocalDatabase.getCachedDocumentDetail(
        ApiClient.tenantId ?? '', 'bill', id,
      );
      if (cached != null) return BillModel.fromJson(cached);
    }
    return null;
  }

  Future<bool> createBill(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'create_bill',
        endpoint: '${ApiClient.baseUrl}/bills',
        method: 'POST',
        body: body,
      );
      if (queued) {
        // Optimistic UI: add placeholder to local list
        final placeholder = {
          'id': 'pending-${DateTime.now().millisecondsSinceEpoch}',
          'bill_number': payload['bill_number'] ?? 'Pending',
          'issue_date': payload['issue_date']?.toString() ?? '',
          'status': 'DRAFT',
          'total': 0.0,
          'amount_paid': 0.0,
          'contact_name': '',
        };
        _bills.insert(0, placeholder);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/bills'),
        body: body,
      );
      if (response.statusCode == 201) {
        await fetchBills();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to create bill';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<BillModel?> previewBill(Map<String, dynamic> payload) async {
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/bills/preview'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return BillModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateBill(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final body = jsonEncode(payload);
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'update_bill',
        endpoint: '${ApiClient.baseUrl}/bills/$id',
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
        _buildUri('${ApiClient.baseUrl}/bills/$id'),
        body: body,
      );
      if (response.statusCode == 200) {
        await fetchBills();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to update bill';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> cancelBill(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'cancel_bill',
        endpoint: '${ApiClient.baseUrl}/bills/$id/cancel',
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
        _buildUri('${ApiClient.baseUrl}/bills/$id/cancel'),
      );
      if (response.statusCode == 200) {
        await fetchBills();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to cancel bill';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> finalizeBill(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'finalize_bill',
        endpoint: '${ApiClient.baseUrl}/bills/$id/finalize',
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
        _buildUri('${ApiClient.baseUrl}/bills/$id/finalize'),
      );
      if (response.statusCode == 200) {
        await fetchBills();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to finalize bill';
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
        action: 'record_bill_payment',
        endpoint: '${ApiClient.baseUrl}/bills/$id/payment',
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
        _buildUri('${ApiClient.baseUrl}/bills/$id/payment'),
        body: body,
      );
      if (response.statusCode == 200) {
        await fetchBills();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to record bill payment';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> deleteBill(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    if (SyncManager.instance != null && !SyncManager.instance!.isOnline) {
      final queued = await SyncManager.instance!.handleWrite(
        action: 'delete_bill',
        endpoint: '${ApiClient.baseUrl}/bills/$id',
        method: 'DELETE',
      );
      if (queued) {
        _bills.removeWhere((b) => b.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      }
    }
    try {
      final response = await _client.delete(
        _buildUri('${ApiClient.baseUrl}/bills/$id'),
      );
      if (response.statusCode == 204 || response.statusCode == 200) {
        await fetchBills();
        return true;
      } else {
        _errorMessage = ApiClient.parseError(response.body, fallback: 'Failed to delete vendor bill');
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
