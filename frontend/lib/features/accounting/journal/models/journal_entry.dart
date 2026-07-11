/// Journal entry model — mirrors backend JournalEntryResponse.
library;

import 'package:flutter/foundation.dart';
import 'journal_line.dart';

@immutable
class JournalEntry {
  const JournalEntry({
    required this.id,
    this.tenantId = '',
    this.entryDate = '',
    this.referenceNumber = '',
    this.description = '',
    this.sourceType = 'MANUAL',
    this.sourceId,
    this.lines = const [],
    this.createdAt,
  });

  final String id;
  final String tenantId;
  final String entryDate;
  final String referenceNumber;
  final String description;
  final String sourceType;
  final String? sourceId;
  final List<JournalLine> lines;
  final String? createdAt;

  /// Total debit amount across all lines.
  double get totalDebit => lines
      .where((l) => l.direction.isDebit)
      .fold<double>(0, (s, l) => s + l.amount);

  /// Total credit amount across all lines.
  double get totalCredit => lines
      .where((l) => l.direction.isCredit)
      .fold<double>(0, (s, l) => s + l.amount);

  /// Whether the entry is balanced (debit == credit).
  bool get isBalanced => (totalDebit - totalCredit).abs() < 0.01;

  Map<String, dynamic> toCreatePayload() => {
    'entry_date': entryDate,
    if (referenceNumber.isNotEmpty) 'reference_number': referenceNumber,
    'description': description,
    'lines': lines.map((l) => l.toCreatePayload()).toList(),
  };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    id: (json['id'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
    entryDate: json['entry_date'] as String? ?? '',
    referenceNumber: json['reference_number'] as String? ?? '',
    description: json['description'] as String? ?? '',
    sourceType: json['source_type'] as String? ?? 'MANUAL',
    sourceId: json['source_id']?.toString(),
    lines:
        (json['lines'] as List?)
            ?.map((e) => JournalLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    createdAt: json['created_at'] as String?,
  );
}
