/// Balance Sheet report models — mirrors backend BalanceSheetResponse.
library;

import 'package:flutter/foundation.dart';

@immutable
class BalanceSheetItem {
  const BalanceSheetItem({
    this.accountName = '',
    this.accountCode = '',
    this.balance = 0,
  });

  final String accountName;
  final String accountCode;
  final double balance;

  factory BalanceSheetItem.fromJson(Map<String, dynamic> json) =>
      BalanceSheetItem(
        accountName: json['account_name'] as String? ?? '',
        accountCode: json['account_code'] as String? ?? '',
        balance: _num(json['balance']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

@immutable
class BalanceSheetReport {
  const BalanceSheetReport({
    this.assets = const [],
    this.totalAssets = 0,
    this.liabilities = const [],
    this.totalLiabilities = 0,
    this.equity = const [],
    this.totalEquity = 0,
    this.netProfit = 0,
  });

  final List<BalanceSheetItem> assets;
  final double totalAssets;
  final List<BalanceSheetItem> liabilities;
  final double totalLiabilities;
  final List<BalanceSheetItem> equity;
  final double totalEquity;
  final double netProfit;

  /// Total liabilities and equity (the balancing side). The API's
  /// `total_equity` already includes the current-period profit line.
  double get totalLiabilitiesEquity => totalLiabilities + totalEquity;

  /// Whether the balance sheet balances (Assets = Liabilities + Equity).
  bool get isBalanced => (totalAssets - totalLiabilitiesEquity).abs() < 0.01;

  factory BalanceSheetReport.fromJson(
    Map<String, dynamic> json,
  ) => BalanceSheetReport(
    assets:
        (json['assets'] as List?)
            ?.map((e) => BalanceSheetItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalAssets: _num(json['total_assets']),
    liabilities:
        (json['liabilities'] as List?)
            ?.map((e) => BalanceSheetItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalLiabilities: _num(json['total_liabilities']),
    equity:
        (json['equity'] as List?)
            ?.map((e) => BalanceSheetItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalEquity: _num(json['total_equity']),
    netProfit: _num(json['net_profit']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
