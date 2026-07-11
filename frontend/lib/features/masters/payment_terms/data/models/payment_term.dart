/// Payment Term model — matches PaymentTermResponse from the backend.
/// Payment terms are read-only (seeded globally, no CRUD endpoints).
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/api/base_model.dart';

@immutable
class PaymentTerm extends BaseModel {
  const PaymentTerm({
    required this.id,
    this.name = '',
    this.dueDays = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final int dueDays;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  /// Human label e.g. "Net 30 (30 days)"
  String get displayLabel => dueDays == 0 ? name : '$name ($dueDays days)';

  @override
  PaymentTerm fromJson(Map<String, dynamic> json) => PaymentTerm(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    dueDays: json['due_days'] as int? ?? 0,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => throw UnsupportedError('Read-only');
}
