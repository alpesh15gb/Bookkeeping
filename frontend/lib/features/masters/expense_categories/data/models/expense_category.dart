/// Expense Category model — matches ExpenseCategoryResponse / ExpenseCategoryCreate
/// / ExpenseCategoryUpdate from the backend (`src/schemas/master_schemas.py`).
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/api/base_model.dart';

@immutable
class ExpenseCategory extends BaseModel {
  const ExpenseCategory({
    required this.id,
    this.name = '',
    this.description,
    this.linkedAccountId,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final String? description;
  final String? linkedAccountId;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  @override
  ExpenseCategory fromJson(Map<String, dynamic> json) => ExpenseCategory(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    linkedAccountId: json['linked_account_id']?.toString(),
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (linkedAccountId != null) 'linked_account_id': linkedAccountId,
  };

  Map<String, dynamic> toUpdateJson() => {
    if (name.isNotEmpty) 'name': name,
    if (description != null) 'description': description,
    'linked_account_id': linkedAccountId,
    'is_active': isActive,
  };

  ExpenseCategory copyWith({
    String? id,
    String? name,
    String? description,
    String? linkedAccountId,
    bool? isActive,
  }) => ExpenseCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    linkedAccountId: linkedAccountId ?? this.linkedAccountId,
    isActive: isActive ?? this.isActive,
  );
}
