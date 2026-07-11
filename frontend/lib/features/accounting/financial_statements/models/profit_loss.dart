/// Profit & Loss report models — mirrors backend ProfitLossResponse.
library;

import 'package:flutter/foundation.dart';

@immutable
class ProfitLossItem {
  const ProfitLossItem({
    this.accountName = '',
    this.accountCode = '',
    this.amount = 0,
  });

  final String accountName;
  final String accountCode;
  final double amount;

  factory ProfitLossItem.fromJson(Map<String, dynamic> json) => ProfitLossItem(
    accountName: json['account_name'] as String? ?? '',
    accountCode: json['account_code'] as String? ?? '',
    amount: _num(json['amount']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

@immutable
class ProfitLossReport {
  const ProfitLossReport({
    this.revenueLines = const [],
    this.totalRevenue = 0,
    this.expenseLines = const [],
    this.totalExpenses = 0,
    this.netProfit = 0,
  });

  final List<ProfitLossItem> revenueLines;
  final double totalRevenue;
  final List<ProfitLossItem> expenseLines;
  final double totalExpenses;
  final double netProfit;

  bool get isProfitable => netProfit >= 0;

  factory ProfitLossReport.fromJson(Map<String, dynamic> json) =>
      ProfitLossReport(
        revenueLines:
            (json['revenue_lines'] as List?)
                ?.map((e) => ProfitLossItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalRevenue: _num(json['total_revenue']),
        expenseLines:
            (json['expense_lines'] as List?)
                ?.map((e) => ProfitLossItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalExpenses: _num(json['total_expenses']),
        netProfit: _num(json['net_profit']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
