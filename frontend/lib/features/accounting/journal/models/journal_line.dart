/// Journal line model — mirrors backend JournalLineResponse.
library;

import 'package:flutter/foundation.dart';
import 'direction.dart';

@immutable
class JournalLine {
  const JournalLine({
    this.id,
    this.accountId = '',
    this.accountName = '',
    this.accountCode = '',
    this.amount = 0,
    this.direction = Direction.debit,
    this.narration,
  });

  final String? id;
  final String accountId;
  final String accountName;
  final String accountCode;
  final double amount;
  final Direction direction;
  final String? narration;

  /// Whether this line has a valid account selected.
  bool get isValid => accountId.isNotEmpty && amount > 0;

  JournalLine copyWith({
    String? id,
    String? accountId,
    String? accountName,
    String? accountCode,
    double? amount,
    Direction? direction,
    String? narration,
    bool clearNarration = false,
  }) => JournalLine(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    accountName: accountName ?? this.accountName,
    accountCode: accountCode ?? this.accountCode,
    amount: amount ?? this.amount,
    direction: direction ?? this.direction,
    narration: clearNarration ? null : (narration ?? this.narration),
  );

  Map<String, dynamic> toCreatePayload() => {
    'account_id': accountId,
    'amount': amount,
    'direction': direction.value,
    if (narration != null) 'narration': narration,
  };

  factory JournalLine.fromJson(Map<String, dynamic> json) => JournalLine(
    id: json['id']?.toString(),
    accountId: (json['account_id'] ?? '').toString(),
    accountName: json['account_name'] as String? ?? '',
    accountCode: json['account_code'] as String? ?? '',
    amount: _num(json['amount']),
    direction: Direction.fromString(json['direction'] as String? ?? ''),
    narration: json['narration'] as String?,
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
