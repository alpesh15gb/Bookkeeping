/// Cash Book report models — mirrors backend CashBookResponse.
library;

import 'package:flutter/foundation.dart';

@immutable
class CashBookRow {
  const CashBookRow({
    this.date = '',
    this.transactionDetails = '',
    this.invoiceAmount,
    this.taxAmount,
    this.amount = 0,
  });

  final String date;
  final String transactionDetails;
  final double? invoiceAmount;
  final double? taxAmount;
  final double amount;

  factory CashBookRow.fromJson(Map<String, dynamic> json) => CashBookRow(
    date: json['date'] as String? ?? '',
    transactionDetails: json['transaction_details'] as String? ?? '',
    invoiceAmount: _optNum(json['invoice_amount']),
    taxAmount: _optNum(json['tax_amount']),
    amount: _num(json['amount']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static double? _optNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final p = double.tryParse(v);
      return p;
    }
    return null;
  }
}

@immutable
class CashBookReport {
  const CashBookReport({
    this.periodStart = '',
    this.periodEnd = '',
    this.openingBalance = 0,
    this.inflows = const [],
    this.outflows = const [],
    this.cashInflow = 0,
    this.cashOutflow = 0,
    this.closingBalance = 0,
  });

  final String periodStart;
  final String periodEnd;
  final double openingBalance;
  final List<CashBookRow> inflows;
  final List<CashBookRow> outflows;
  final double cashInflow;
  final double cashOutflow;
  final double closingBalance;

  factory CashBookReport.fromJson(Map<String, dynamic> json) => CashBookReport(
    periodStart: json['period_start'] as String? ?? '',
    periodEnd: json['period_end'] as String? ?? '',
    openingBalance: _num(json['opening_balance']),
    inflows:
        (json['inflows'] as List?)
            ?.map((e) => CashBookRow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    outflows:
        (json['outflows'] as List?)
            ?.map((e) => CashBookRow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    cashInflow: _num(
      (json['summary'] as Map<String, dynamic>?)?['cash_inflow'],
    ),
    cashOutflow: _num(
      (json['summary'] as Map<String, dynamic>?)?['cash_outflow'],
    ),
    closingBalance: _num(
      (json['summary'] as Map<String, dynamic>?)?['closing_balance'],
    ),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
