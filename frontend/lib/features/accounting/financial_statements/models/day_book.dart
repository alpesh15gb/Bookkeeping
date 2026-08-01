/// Day Book report models — mirrors backend DayBookResponse.
library;

import 'package:flutter/foundation.dart';

@immutable
class DayBookLine {
  const DayBookLine({
    this.accountId = '',
    this.accountName = '',
    this.accountCode = '',
    this.amount = 0,
    this.direction = '',
    this.narration,
  });

  final String accountId;
  final String accountName;
  final String accountCode;
  final double amount;
  final String direction;
  final String? narration;

  bool get isDebit => direction == 'DEBIT';

  factory DayBookLine.fromJson(Map<String, dynamic> json) => DayBookLine(
    accountId: json['account_id'] as String? ?? '',
    accountName: json['account_name'] as String? ?? '',
    accountCode: json['account_code'] as String? ?? '',
    amount: _num(json['amount']),
    direction: json['direction'] as String? ?? '',
    narration: json['narration'] as String?,
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

@immutable
class DayBookEntry {
  const DayBookEntry({
    this.id = '',
    this.entryDate = '',
    this.referenceNumber = '',
    this.description = '',
    this.sourceType = '',
    this.sourceId,
    this.lines = const [],
  });

  final String id;
  final String entryDate;
  final String referenceNumber;
  final String description;
  final String sourceType;
  final String? sourceId;
  final List<DayBookLine> lines;

  factory DayBookEntry.fromJson(Map<String, dynamic> json) => DayBookEntry(
    id: json['id'] as String? ?? '',
    entryDate: json['entry_date'] as String? ?? '',
    referenceNumber: json['reference_number'] as String? ?? '',
    description: json['description'] as String? ?? '',
    sourceType: json['source_type'] as String? ?? '',
    sourceId: json['source_id'] as String?,
    lines:
        (json['lines'] as List?)
            ?.map((e) => DayBookLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

@immutable
class DayBookReport {
  const DayBookReport({
    this.startDate = '',
    this.endDate = '',
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.entries = const [],
    this.totalCount = 0,
  });

  final String startDate;
  final String endDate;
  final double totalDebit;
  final double totalCredit;
  final List<DayBookEntry> entries;
  final int totalCount;

  factory DayBookReport.fromJson(Map<String, dynamic> json) => DayBookReport(
    startDate: json['start_date'] as String? ?? '',
    endDate: json['end_date'] as String? ?? '',
    totalDebit: _num(json['total_debit']),
    totalCredit: _num(json['total_credit']),
    entries:
        (json['entries'] as List?)
            ?.map((e) => DayBookEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    totalCount: json['total_count'] as int? ?? 0,
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
