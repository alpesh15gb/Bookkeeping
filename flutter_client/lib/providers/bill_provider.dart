import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/bill.dart';

class BillProvider extends ChangeNotifier {
  List<BillModel> _bills = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<BillModel> get bills => _bills;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  final ApiClient _client = ApiClient();

  Future<void> fetchBills() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/bills'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data is Map ? (data['items'] ?? []) : data;
        _bills = items.map((x) => BillModel.fromJson(x)).toList();
      } else {
        _errorMessage = 'Failed to load vendor bills';
      }
    } catch (e) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BillModel?> fetchBillDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/bills/$id'));
      if (response.statusCode == 200) {
        return BillModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> createBill(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/bills'),
        body: jsonEncode(payload),
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
        Uri.parse('${ApiClient.baseUrl}/bills/preview'),
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
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/bills/$id'),
        body: jsonEncode(payload),
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
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/bills/$id/cancel'),
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
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/bills/$id/finalize'),
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
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/bills/$id/payment'),
        body: jsonEncode(payload),
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
    try {
      final response = await _client.delete(
        Uri.parse('${ApiClient.baseUrl}/bills/$id'),
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

