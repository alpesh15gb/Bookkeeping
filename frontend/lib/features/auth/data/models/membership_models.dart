/// Multi-tenancy models: [MemberRole], [Membership] and [Company].
///
/// These describe the companies a user belongs to (`GET /auth/memberships`)
/// and the full company profile (`GET /companies/{id}`).
library;

import 'package:flutter/foundation.dart';

/// Role assigned to a user within a tenant.
enum MemberRole { owner, accountant, salesperson, auditor }

extension MemberRoleX on MemberRole {
  /// The wire value used by the backend (`owner`, `accountant`, ...).
  String get wire => name;

  /// Human-readable label shown in the UI.
  String get label {
    switch (this) {
      case MemberRole.owner:
        return 'Owner';
      case MemberRole.accountant:
        return 'Accountant';
      case MemberRole.salesperson:
        return 'Salesperson';
      case MemberRole.auditor:
        return 'Auditor';
    }
  }

  static MemberRole fromWire(String? value) {
    switch (value) {
      case 'owner':
        return MemberRole.owner;
      case 'accountant':
        return MemberRole.accountant;
      case 'salesperson':
        return MemberRole.salesperson;
      case 'auditor':
        return MemberRole.auditor;
      default:
        return MemberRole.owner;
    }
  }
}

/// Response from `GET /auth/memberships` — one entry per tenant the user
/// belongs to. The backend may return tenant fields inline or nested; both
/// shapes are tolerated.
@immutable
class Membership {
  const Membership({
    required this.id,
    required this.tenantId,
    required this.role,
    required this.isActive,
    required this.legalName,
    this.tradeName,
    this.gstin,
    this.pan,
    this.taxMode,
  });

  factory Membership.fromJson(Map<String, dynamic> json) {
    // Some backends nest the tenant under `tenant`; others flatten it.
    final tenant = (json['tenant'] as Map<String, dynamic>?) ?? const {};
    return Membership(
      id: json['id'] as String,
      tenantId:
          (json['tenant_id'] as String?) ?? (tenant['id'] as String?) ?? '',
      role: MemberRoleX.fromWire(json['role'] as String?),
      isActive: (json['is_active'] as bool?) ?? true,
      legalName:
          (json['legal_name'] as String?) ??
          (tenant['legal_name'] as String?) ??
          (json['tenant_name'] as String?) ??
          'Untitled Company',
      tradeName:
          (json['trade_name'] as String?) ?? (tenant['trade_name'] as String?),
      gstin: (json['gstin'] as String?) ?? (tenant['gstin'] as String?),
      pan: (json['pan'] as String?) ?? (tenant['pan'] as String?),
      taxMode: (json['tax_mode'] as String?) ?? (tenant['tax_mode'] as String?),
    );
  }

  final String id;
  final String tenantId;
  final MemberRole role;
  final bool isActive;
  final String legalName;
  final String? tradeName;
  final String? gstin;
  final String? pan;
  final String? taxMode;

  /// The display name preferred across the UI (trade name falls back to legal).
  String get displayName =>
      (tradeName?.isNotEmpty ?? false) ? tradeName! : legalName;
}

/// Company (tenant) shape returned by `GET /companies/{id}` and `POST /companies`.
@immutable
class Company {
  const Company({
    required this.id,
    required this.legalName,
    this.tradeName,
    this.gstin,
    this.pan,
    required this.taxMode,
    required this.financialYearStart,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      legalName: json['legal_name'] as String,
      tradeName: json['trade_name'] as String?,
      gstin: json['gstin'] as String?,
      pan: json['pan'] as String?,
      taxMode: (json['tax_mode'] as String?) ?? 'NON_GST',
      financialYearStart: DateTime.parse(
        (json['financial_year_start'] as String?) ?? '2026-04-01',
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final String legalName;
  final String? tradeName;
  final String? gstin;
  final String? pan;
  final String taxMode;
  final DateTime financialYearStart;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName =>
      (tradeName?.isNotEmpty ?? false) ? tradeName! : legalName;
}
