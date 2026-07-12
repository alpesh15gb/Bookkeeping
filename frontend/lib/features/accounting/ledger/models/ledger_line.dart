/// Ledger line — mirrors backend LedgerLine schema.
library;

import 'package:flutter/foundation.dart';

@immutable
class LedgerLine {
  const LedgerLine({
    this.entryDate = '',
    this.referenceNumber = '',
    this.voucherType = '',
    this.description = '',
    this.debitAmount = 0,
    this.creditAmount = 0,
    this.narration,
    this.runningBalance = 0,
  });

  final String entryDate;
  final String referenceNumber;
  final String voucherType;
  final String description;
  final double debitAmount;
  final double creditAmount;
  final String? narration;
  final double runningBalance;

  factory LedgerLine.fromJson(Map<String, dynamic> json) => LedgerLine(
    entryDate: json['entry_date'] as String? ?? '',
    referenceNumber: json['reference_number'] as String? ?? '',
    voucherType: json['voucher_type'] as String? ?? '',
    description: json['description'] as String? ?? '',
    debitAmount: _num(json['debit_amount']),
    creditAmount: _num(json['credit_amount']),
    narration: json['narration'] as String?,
    runningBalance: _num(json['running_balance']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
