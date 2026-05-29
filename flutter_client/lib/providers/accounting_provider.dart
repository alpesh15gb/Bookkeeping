import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

class AccountingProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic>? _accountsList;
  Map<String, dynamic>? _currentLedger;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<dynamic>? get accountsList => _accountsList;
  Map<String, dynamic>? get currentLedger => _currentLedger;

  final ApiClient _client = ApiClient();

  // Journals
  Future<List<dynamic>> fetchJournals() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/journals'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return [];
  }

  Future<bool> createJournal(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/accounting/journals'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final data = jsonDecode(response.body);
        _errorMessage = data['detail'] ?? 'Failed to create journal';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  // General Ledger statement for account_id
  Future<Map<String, dynamic>?> fetchLedgerStatement(String accountId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/ledger/$accountId'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Trial Balance
  Future<Map<String, dynamic>?> fetchTrialBalance() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/trial-balance'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Profit & Loss
  Future<Map<String, dynamic>?> fetchProfitLoss() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/profit-loss'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Balance Sheet
  Future<Map<String, dynamic>?> fetchBalanceSheet() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/balance-sheet'));
      if (response.statusCode == 200) {
        _isLoading = false;
        notifyListeners();
        return jsonDecode(response.body);
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return null;
  }

  // Chart of Accounts / Accounts CRUD
  Future<void> fetchAccounts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/accounts'));
      if (response.statusCode == 200) {
        _accountsList = jsonDecode(response.body) as List;
      } else {
        _errorMessage = 'Failed to load accounts';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createAccount(Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.post(
        Uri.parse('${ApiClient.baseUrl}/masters/accounts'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 201) {
        await fetchAccounts();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to create account';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateAccount(String id, Map<String, dynamic> payload) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.put(
        Uri.parse('${ApiClient.baseUrl}/masters/accounts/$id'),
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        await fetchAccounts();
        return true;
      }
      final data = jsonDecode(response.body);
      _errorMessage = data['detail'] ?? 'Failed to update account';
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<Map<String, dynamic>?> fetchAccountDetail(String id) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/masters/accounts/$id'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> deleteAccount(String id) async {
    try {
      final response = await _client.delete(Uri.parse('${ApiClient.baseUrl}/masters/accounts/$id'));
      if (response.statusCode == 204) {
        await fetchAccounts();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> fetchLedger(String accountId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/ledger/$accountId'));
      if (response.statusCode == 200) {
        _currentLedger = jsonDecode(response.body);
      } else {
        _errorMessage = 'Failed to load ledger';
      }
    } catch (_) {
      _errorMessage = 'An error occurred';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> fetchGstr1(String start, String end) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/gst/gstr1?start_date=$start&end_date=$end'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchGstr3b(String start, String end) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/gst/gstr3b?start_date=$start&end_date=$end'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchReceivablesAging(String asOf) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/aging/receivables?as_of_date=$asOf'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchPayablesAging(String asOf) async {
    try {
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/aging/payables?as_of_date=$asOf'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchCashFlow({String? startDate, String? endDate}) async {
    try {
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/cash-flow$query'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchSalesAnalytics({String? startDate, String? endDate}) async {
    try {
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/analytics/sales$query'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchPurchaseAnalytics({String? startDate, String? endDate}) async {
    try {
      final params = <String>[];
      if (startDate != null) params.add('start_date=$startDate');
      if (endDate != null) params.add('end_date=$endDate');
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/analytics/purchases$query'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchOutstandingReceivables({String? asOfDate}) async {
    try {
      final query = asOfDate != null ? '?as_of_date=$asOfDate' : '';
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/outstanding/receivables$query'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> fetchOutstandingPayables({String? asOfDate}) async {
    try {
      final query = asOfDate != null ? '?as_of_date=$asOfDate' : '';
      final response = await _client.get(Uri.parse('${ApiClient.baseUrl}/reports/outstanding/payables$query'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
