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
      total += (_metrics[key] as num?)?.toDouble() ?? 0;
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

      _salesSummary = jsonDecode(core[0].body) as Map<String, dynamic>;
      
      final expRaw = jsonDecode(core[1].body);
      if (expRaw is List) {
        _expenses = expRaw;
      } else if (expRaw is Map<String, dynamic>) {
        _expenses = (expRaw['items'] as List?) ?? [];
      } else {
        _expenses = [];
      }

      final billsRaw = jsonDecode(core[2].body);
      if (billsRaw is List) {
        _bills = billsRaw;
      } else if (billsRaw is Map<String, dynamic>) {
        _bills = (billsRaw['items'] as List?) ?? [];
      } else {
        _bills = [];
      }

      _metrics = jsonDecode(core[3].body) as Map<String, dynamic>;
      final invRaw = jsonDecode(core[4].body);
      if (invRaw is List) {
        _recentInvoices = invRaw;
      } else if (invRaw is Map<String, dynamic>) {
        _recentInvoices = (invRaw['items'] as List?) ?? [];
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

      if (secondary[0].statusCode == 200) _revenueTrend = jsonDecode(secondary[0].body) as List? ?? [];
      if (secondary[1].statusCode == 200) _expenseTrend = jsonDecode(secondary[1].body) as List? ?? [];
      if (secondary[2].statusCode == 200) _cashBankBalances = jsonDecode(secondary[2].body) as List? ?? [];

      // Parse top debtors from receivables
      try {
        if (secondary[3].statusCode == 200) {
          final arData = jsonDecode(secondary[3].body);
          final items = (arData['invoices'] as List?) ?? [];
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
