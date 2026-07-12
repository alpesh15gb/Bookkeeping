/// General ledger report — mirrors backend LedgerReportResponse.
library;

import 'package:flutter/foundation.dart';
import 'ledger_line.dart';

@immutable
class LedgerReport {
  const LedgerReport({
    this.accountId = '',
    this.accountName = '',
    this.accountCode = '',
    this.openingBalance = 0,
    this.closingBalance = 0,
    this.lines = const [],
    this.totalLines = 0,
  });

  final String accountId;
  final String accountName;
  final String accountCode;
  final double openingBalance;
  final double closingBalance;
  final List<LedgerLine> lines;
  final int totalLines;

  /// Compute the total debits from the ledger lines.
  double get totalDebits => lines.fold<double>(0, (s, l) => s + l.debitAmount);

  /// Compute the total credits from the ledger lines.
  double get totalCredits =>
      lines.fold<double>(0, (s, l) => s + l.creditAmount);

  factory LedgerReport.fromJson(Map<String, dynamic> json) => LedgerReport(
    accountId: (json['account_id'] ?? '').toString(),
    accountName: json['account_name'] as String? ?? '',
    accountCode: json['account_code'] as String? ?? '',
    openingBalance: _num(json['opening_balance']),
    closingBalance: _num(json['closing_balance']),
    lines:
        (json['lines'] as List?)
            ?.map((e) => LedgerLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalLines: _int(json['total_lines']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _int(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is num) return v.toInt();
    return 0;
  }
}
