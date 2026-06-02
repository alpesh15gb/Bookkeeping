import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:http/http.dart' as http;

class DashboardProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic> _metrics = {};
  Map<String, dynamic> _salesSummary = {};
  List<dynamic> _expenses = [];
  List<dynamic> _bills = [];
  List<dynamic> _recentInvoices = [];
  List<dynamic> _revenueTrend = [];
  List<dynamic> _expenseTrend = [];
  List<dynamic> _cashBankBalances = [];
  List<dynamic> _topDebtors = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic> get metrics => _metrics;
  Map<String, dynamic> get salesSummary => _salesSummary;
  List<dynamic> get recentInvoices => _recentInvoices;
  List<dynamic> get revenueTrend => _revenueTrend;
  List<dynamic> get expenseTrend => _expenseTrend;
  List<dynamic> get cashBankBalances => _cashBankBalances;
  List<dynamic> get topDebtors => _topDebtors;

  double get revenue => _safeDouble(_salesSummary['total_sales']);
  double get cashReceived => _safeDouble(_salesSummary['total_received']);
  double get receivables => _safeDouble(_salesSummary['outstanding']);
  double get totalGstLiability => _safeDouble(_salesSummary['total_gst_liability']);

  double get totalExpenses => _expenses
      .where((e) => e['status'] == 'POSTED')
      .fold(0.0, (sum, e) => sum + _safeDouble(e['total']));

  double get purchases => _bills
      .where((b) => b['status'] != 'DRAFT' && b['status'] != 'CANCELLED')
      .fold(0.0, (sum, b) => sum + _safeDouble(b['total']));

  double get netProfit => revenue - totalExpenses - purchases;

  double get payables => _bills
      .where((b) => b['status'] != 'DRAFT' && b['status'] != 'CANCELLED')
      .fold(0.0, (sum, b) {
        final total = _safeDouble(b['total']);
        final amountPaid = _safeDouble(b['amount_paid']);
        return sum + (total - amountPaid);
      });

  double get totalTax {
    double total = 0;
    for (final key in ['cgst_total', 'sgst_total', 'igst_total', 'cess_total']) {
      total += _safeDouble(_metrics[key]);
    }
    return total;
  }

  double _safeDouble(dynamic val) => double.tryParse((val ?? 0).toString()) ?? 0.0;

  final ApiClient _client = ApiClient();

  Future<void> fetchDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Core endpoints — these must succeed
      final core = await Future.wait([
        _client.get(Uri.parse('${ApiClient.baseUrl}/sales/summary')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/expenses')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/bills')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/dashboard/metrics')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/invoices?limit=5')),
      ]);

      final coreFail = core.any((r) => r.statusCode != 200);
      if (coreFail) {
        final bad = core.where((r) => r.statusCode != 200).map((r) => '${r.request?.url}: ${r.statusCode}').join(', ');
        _errorMessage = 'API error: $bad';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final salesData = jsonDecode(core[0].body);
      _salesSummary = salesData is Map<String, dynamic> ? salesData : Map<String, dynamic>.from(salesData is Map ? salesData : {});
      
      final expRaw = jsonDecode(core[1].body);
      if (expRaw is List) {
        _expenses = expRaw;
      } else if (expRaw is Map) {
        final expItems = expRaw['items'];
        _expenses = expItems is List ? expItems : [];
      } else {
        _expenses = [];
      }

      final billsRaw = jsonDecode(core[2].body);
      if (billsRaw is List) {
        _bills = billsRaw;
      } else if (billsRaw is Map) {
        final billItems = billsRaw['items'];
        _bills = billItems is List ? billItems : [];
      } else {
        _bills = [];
      }

      final metricsData = jsonDecode(core[3].body);
      _metrics = metricsData is Map<String, dynamic> ? metricsData : Map<String, dynamic>.from(metricsData is Map ? metricsData : {});
      final invRaw = jsonDecode(core[4].body);
      if (invRaw is List) {
        _recentInvoices = invRaw;
      } else if (invRaw is Map) {
        final invItems = invRaw['items'];
        _recentInvoices = invItems is List ? invItems : [];
      } else {
        _recentInvoices = [];
      }

      // Trend + supplementary endpoints — all parallel, fail silently
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final secondary = await Future.wait([
        _client.get(Uri.parse('${ApiClient.baseUrl}/dashboard/revenue-trend'))
            .catchError((_) => http.Response('[]', 500)),
        _client.get(Uri.parse('${ApiClient.baseUrl}/dashboard/expense-trend'))
            .catchError((_) => http.Response('[]', 500)),
        _client.get(Uri.parse('${ApiClient.baseUrl}/accounting/cash-bank-balances'))
            .catchError((_) => http.Response('[]', 500)),
        _client.get(Uri.parse('${ApiClient.baseUrl}/reports/outstanding/receivables?as_of_date=$dateStr'))
            .catchError((_) => http.Response('{}', 500)),
      ]);

      if (secondary[0].statusCode == 200) {
        final d = jsonDecode(secondary[0].body);
        _revenueTrend = d is List ? d : [];
      }
      if (secondary[1].statusCode == 200) {
        final d = jsonDecode(secondary[1].body);
        _expenseTrend = d is List ? d : [];
      }
      if (secondary[2].statusCode == 200) {
        final d = jsonDecode(secondary[2].body);
        _cashBankBalances = d is List ? d : [];
      }

      // Parse top debtors from receivables
      try {
        if (secondary[3].statusCode == 200) {
          final arData = jsonDecode(secondary[3].body);
          final arInvoices = arData is Map ? arData['invoices'] : null;
          final items = arInvoices is List ? arInvoices : [];
          final Map<String, double> debtorMap = {};
          for (final inv in items) {
            final name = inv['contact_name'] ?? 'Unknown';
            final outstanding = double.tryParse((inv['outstanding_amount'] ?? 0).toString()) ?? 0.0;
            debtorMap[name] = (debtorMap[name] ?? 0.0) + outstanding;
          }
          final sorted = debtorMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          _topDebtors = sorted.take(5).map((e) => {'name': e.key, 'outstanding': e.value}).toList();
        }
      } catch (_) {}

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Connection failed. Please check your network.';
      _isLoading = false;
      notifyListeners();
    }
  }
}
