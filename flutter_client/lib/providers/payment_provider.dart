import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/models/payment.dart';

class PaymentProvider extends ChangeNotifier {
  List<PaymentModel> _receipts = [];
  List<BillPaymentModel> _disbursements = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<PaymentModel> get receipts => _receipts;
  List<BillPaymentModel> get disbursements => _disbursements;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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

  Future<void> fetchReceipts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/payments/receipts'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data is Map ? (data['items'] ?? []) : (data is List ? data : []);
        _receipts = items.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).whereType<Map<String, dynamic>>().map((x) => PaymentModel.fromJson(x)).toList();
      }
    } catch (_) {
      _errorMessage = 'Failed to load receipts';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDisbursements() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/payments/disbursements'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data is Map ? (data['items'] ?? []) : (data is List ? data : []);
        _disbursements = items.map((e) => e is Map ? Map<String, dynamic>.from(e) : null).whereType<Map<String, dynamic>>().map((x) => BillPaymentModel.fromJson(x)).toList();
      }
    } catch (_) {
      _errorMessage = 'Failed to load disbursements';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createReceipt(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/payments/receipts'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchReceipts();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create receipt';
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> createDisbursement(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/payments/disbursements'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchDisbursements();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create disbursement';
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<PaymentModel?> fetchReceiptDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/payments/receipts/$id'));
      if (response.statusCode == 200) {
        return PaymentModel.fromJson(jsonDecode(response.body));
      }
      _errorMessage = 'Failed to load receipt (${response.statusCode})';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load receipt';
      notifyListeners();
    }
    return null;
  }

  Future<BillPaymentModel?> fetchDisbursementDetail(String id) async {
    try {
      final response = await _client.get(_buildUri('${ApiClient.baseUrl}/payments/disbursements/$id'));
      if (response.statusCode == 200) {
        return BillPaymentModel.fromJson(jsonDecode(response.body));
      }
      _errorMessage = 'Failed to load disbursement (${response.statusCode})';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load disbursement';
      notifyListeners();
    }
    return null;
  }

  Future<bool> cancelReceipt(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/payments/receipts/$id/cancel'),
      );
      if (response.statusCode == 200) {
        await fetchReceipts();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Cancel receipt failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> cancelDisbursement(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        _buildUri('${ApiClient.baseUrl}/payments/disbursements/$id/cancel'),
      );
      if (response.statusCode == 200) {
        await fetchDisbursements();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Cancel disbursement failed';
    } catch (_) {
      _errorMessage = 'An error occurred';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  Future<bool> cancelReceiptById(String id) async {
    return cancelReceipt(id);
  }

  Future<bool> cancelDisbursementById(String id) async {
    return cancelDisbursement(id);
  }
}
