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

  Future<void> fetchReceipts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/payments/receipts'));
      if (response.statusCode == 200) {
        final List items = jsonDecode(response.body);
        _receipts = items.map((x) => PaymentModel.fromJson(x)).toList();
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
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/payments/disbursements'));
      if (response.statusCode == 200) {
        final List items = jsonDecode(response.body);
        _disbursements = items.map((x) => BillPaymentModel.fromJson(x)).toList();
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
        Uri.parse('${ApiClient.baseUrl}/payments/receipts'),
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
        Uri.parse('${ApiClient.baseUrl}/payments/disbursements'),
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
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/payments/receipts/$id'));
      if (response.statusCode == 200) {
        return PaymentModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<BillPaymentModel?> fetchDisbursementDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/payments/disbursements/$id'));
      if (response.statusCode == 200) {
        return BillPaymentModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> cancelReceipt(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/payments/receipts/$id/cancel'),
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
        Uri.parse('${ApiClient.baseUrl}/payments/disbursements/$id/cancel'),
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

  Future<bool> deleteReceipt(String id) async {
    return cancelReceipt(id);
  }

  Future<bool> deleteDisbursement(String id) async {
    return cancelDisbursement(id);
  }
}
