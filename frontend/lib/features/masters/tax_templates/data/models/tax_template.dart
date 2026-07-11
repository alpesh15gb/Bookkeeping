/// Tax Template model — matches TaxTemplateResponse from the backend.
/// Tax templates are read-only (seeded globally, no CRUD endpoints).
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/api/base_model.dart';

@immutable
class TaxTemplate extends BaseModel {
  const TaxTemplate({
    required this.id,
    this.name = '',
    this.rate = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final double rate;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  /// Formatted label e.g. "GST 18%"
  String get displayLabel => '$name (${rate.toStringAsFixed(0)}%)';

  @override
  TaxTemplate fromJson(Map<String, dynamic> json) => TaxTemplate(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    rate: (json['rate'] as num?)?.toDouble() ?? 0,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => throw UnsupportedError('Read-only');
}
