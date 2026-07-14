/// Financial year model for Settings.
library;

import 'package:flutter/foundation.dart';

/// A financial/assessment year for the company.
@immutable
class FinancialYear {
  const FinancialYear({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.isCurrent = false,
    this.isActive = true,
    this.status = 'UPCOMING',
    this.transactionCount = 0,
    this.createdAt,
  });

  factory FinancialYear.fromJson(Map<String, dynamic> json) {
    return FinancialYear(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isCurrent: (json['is_current'] as bool?) ?? false,
      isActive: !const {'LOCKED', 'ARCHIVED'}.contains(json['status']),
      status: json['status'] as String? ?? 'UPCOMING',
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCurrent;
  final bool isActive;
  final String status;
  final int transactionCount;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate.toIso8601String(),
    'is_current': isCurrent,
    'is_active': isActive,
    'status': status,
    'transaction_count': transactionCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialYear &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
