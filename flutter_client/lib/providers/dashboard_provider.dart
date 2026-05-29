import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_client/core/api_client.dart';

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

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic> get metrics => _metrics;
  Map<String, dynamic> get salesSummary => _salesSummary;
  List<dynamic> get recentInvoices => _recentInvoices;
  List<dynamic> get revenueTrend => _revenueTrend;
  List<dynamic> get expenseTrend => _expenseTrend;

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
    debugPrint('🟡 [Dashboard] fetchDashboard() START');
    debugPrint('🟡 [Dashboard] baseUrl = ${ApiClient.baseUrl}');

    try {
      // Core endpoints — these must succeed
      debugPrint('🟡 [Dashboard] Fetching core endpoints...');
      final core = await Future.wait([
        _client.get(Uri.parse('${ApiClient.baseUrl}/sales/summary')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/expenses')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/bills')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/dashboard/metrics')),
        _client.get(Uri.parse('${ApiClient.baseUrl}/invoices?limit=5')),
      ]);

      debugPrint('🟡 [Dashboard] Core responses: ${core.map((r) => '${r.request?.url.path}: ${r.statusCode}').join(', ')}');

      final coreFail = core.any((r) => r.statusCode != 200);
      if (coreFail) {
        final bad = core.where((r) => r.statusCode != 200).map((r) => '${r.request?.url}: ${r.statusCode}').join(', ');
        debugPrint('❌ [Dashboard] Core API error: $bad');
        _errorMessage = 'API error: $bad';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _salesSummary = jsonDecode(core[0].body) as Map<String, dynamic>;
      _expenses = jsonDecode(core[1].body) as List? ?? [];
      _bills = jsonDecode(core[2].body) as List? ?? [];
      _metrics = jsonDecode(core[3].body) as Map<String, dynamic>;
      final invRaw = jsonDecode(core[4].body);
      if (invRaw is List) {
        _recentInvoices = invRaw;
      } else if (invRaw is Map<String, dynamic>) {
        _recentInvoices = (invRaw['items'] as List?) ?? [];
      } else {
        _recentInvoices = [];
      }

      debugPrint('✅ [Dashboard] Data parsed: revenue=$revenue, expenses=$totalExpenses, invoices=${_recentInvoices.length}');

      // Trend endpoints are non-critical — fail silently
      try {
        final trendRes = await _client.get(Uri.parse('${ApiClient.baseUrl}/dashboard/revenue-trend'));
        if (trendRes.statusCode == 200) _revenueTrend = jsonDecode(trendRes.body) as List? ?? [];
        debugPrint('🟡 [Dashboard] Revenue trend: ${trendRes.statusCode}, ${_revenueTrend.length} items');
      } catch (e) { debugPrint('⚠️ [Dashboard] Revenue trend failed: $e'); }

      try {
        final expenseTrendRes = await _client.get(Uri.parse('${ApiClient.baseUrl}/dashboard/expense-trend'));
        if (expenseTrendRes.statusCode == 200) _expenseTrend = jsonDecode(expenseTrendRes.body) as List? ?? [];
        debugPrint('🟡 [Dashboard] Expense trend: ${expenseTrendRes.statusCode}, ${_expenseTrend.length} items');
      } catch (e) { debugPrint('⚠️ [Dashboard] Expense trend failed: $e'); }

      _isLoading = false;
      debugPrint('✅ [Dashboard] fetchDashboard() COMPLETE');
      notifyListeners();
    } catch (e, stack) {
      debugPrint('❌ [Dashboard] Exception: $e');
      debugPrint('❌ [Dashboard] Stack: $stack');
      _errorMessage = 'Connection failed: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
}
