/// Trial balance models — mirrors backend TrialBalanceResponse.
library;

import 'package:flutter/foundation.dart';

/// A single line in the trial balance.
@immutable
class TrialBalanceLine {
  const TrialBalanceLine({
    this.accountId = '',
    this.accountName = '',
    this.accountCode = '',
    this.accountType = '',
    this.openingBalance = 0,
    this.totalDebits = 0,
    this.totalCredits = 0,
    this.closingBalance = 0,
  });

  final String accountId;
  final String accountName;
  final String accountCode;
  final String accountType;
  final double openingBalance;
  final double totalDebits;
  final double totalCredits;
  final double closingBalance;

  factory TrialBalanceLine.fromJson(Map<String, dynamic> json) =>
      TrialBalanceLine(
        accountId: (json['account_id'] ?? '').toString(),
        accountName: json['account_name'] as String? ?? '',
        accountCode: json['account_code'] as String? ?? '',
        accountType: json['account_type'] as String? ?? '',
        openingBalance: _num(json['opening_balance']),
        totalDebits: _num(json['total_debits']),
        totalCredits: _num(json['total_credits']),
        closingBalance: _num(json['closing_balance']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// Trial balance response with aggregate totals.
@immutable
class TrialBalanceReport {
  const TrialBalanceReport({
    this.lines = const [],
    this.totalOpeningDebits = 0,
    this.totalOpeningCredits = 0,
    this.totalDebits = 0,
    this.totalCredits = 0,
    this.totalClosingDebits = 0,
    this.totalClosingCredits = 0,
  });

  final List<TrialBalanceLine> lines;
  final double totalOpeningDebits;
  final double totalOpeningCredits;
  final double totalDebits;
  final double totalCredits;
  final double totalClosingDebits;
  final double totalClosingCredits;

  /// Whether the trial balance is balanced (opening debits == credits and closing debits == credits).
  bool get isBalanced =>
      (totalOpeningDebits - totalOpeningCredits).abs() < 0.01 &&
      (totalDebits - totalCredits).abs() < 0.01 &&
      (totalClosingDebits - totalClosingCredits).abs() < 0.01;

  factory TrialBalanceReport.fromJson(Map<String, dynamic> json) =>
      TrialBalanceReport(
        lines:
            (json['lines'] as List?)
                ?.map(
                  (e) => TrialBalanceLine.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        totalOpeningDebits: _num(json['total_opening_debits']),
        totalOpeningCredits: _num(json['total_opening_credits']),
        totalDebits: _num(json['total_debits']),
        totalCredits: _num(json['total_credits']),
        totalClosingDebits: _num(json['total_closing_debits']),
        totalClosingCredits: _num(json['total_closing_credits']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
