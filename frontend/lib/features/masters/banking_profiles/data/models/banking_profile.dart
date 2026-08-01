/// Banking Profile model — matches BankingProfileResponse / BankingProfileCreate
/// / BankingProfileUpdate from the backend (`src/schemas/master_schemas.py`).
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/api/base_model.dart';

@immutable
class BankingProfile extends BaseModel {
  const BankingProfile({
    required this.id,
    this.bankName = '',
    this.accountNumber = '',
    this.ifscCode = '',
    this.branchName,
    this.accountHolderName = '',
    this.upiId,
    this.isPrimary = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String bankName;
  final String accountNumber;
  final String ifscCode;
  final String? branchName;
  final String accountHolderName;
  final String? upiId;
  final bool isPrimary;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  /// Masked account number for display (shows last 4 digits).
  String get maskedNumber {
    if (accountNumber.length <= 4) return accountNumber;
    return '••••${accountNumber.substring(accountNumber.length - 4)}';
  }

  /// Short bank+last4 label for dropdowns/cells.
  String get shortLabel => '$bankName ($maskedNumber)';

  @override
  BankingProfile fromJson(Map<String, dynamic> json) => BankingProfile(
    id: (json['id'] ?? '').toString(),
    bankName: json['bank_name'] as String? ?? '',
    accountNumber: json['account_number'] as String? ?? '',
    ifscCode: json['ifsc_code'] as String? ?? '',
    branchName: json['branch_name'] as String?,
    accountHolderName: json['account_holder_name'] as String? ?? '',
    upiId: json['upi_id'] as String?,
    isPrimary: json['is_primary'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'bank_name': bankName,
    'account_number': accountNumber,
    'ifsc_code': ifscCode,
    if (branchName != null) 'branch_name': branchName,
    'account_holder_name': accountHolderName,
    if (upiId != null && upiId!.isNotEmpty) 'upi_id': upiId,
    'is_primary': isPrimary,
  };

  Map<String, dynamic> toUpdateJson() => {
    if (bankName.isNotEmpty) 'bank_name': bankName,
    if (accountNumber.isNotEmpty) 'account_number': accountNumber,
    if (ifscCode.isNotEmpty) 'ifsc_code': ifscCode,
    if (branchName != null) 'branch_name': branchName,
    if (accountHolderName.isNotEmpty) 'account_holder_name': accountHolderName,
    if (upiId != null) 'upi_id': upiId,
    'is_primary': isPrimary,
    'is_active': isActive,
  };

  BankingProfile copyWith({
    String? id,
    String? bankName,
    String? accountNumber,
    String? ifscCode,
    String? branchName,
    String? accountHolderName,
    String? upiId,
    bool? isPrimary,
    bool? isActive,
  }) => BankingProfile(
    id: id ?? this.id,
    bankName: bankName ?? this.bankName,
    accountNumber: accountNumber ?? this.accountNumber,
    ifscCode: ifscCode ?? this.ifscCode,
    branchName: branchName ?? this.branchName,
    accountHolderName: accountHolderName ?? this.accountHolderName,
    upiId: upiId ?? this.upiId,
    isPrimary: isPrimary ?? this.isPrimary,
    isActive: isActive ?? this.isActive,
  );
}

/// Validates IFSC code format (11 chars: 4 letters + 0 + 6 alphanumeric).
String? validateIfsc(String? v) {
  if (v == null || v.trim().isEmpty) return 'IFSC code is required';
  final code = v.trim().toUpperCase();
  if (code.length != 11) return 'IFSC must be exactly 11 characters';
  if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(code)) {
    return 'Invalid IFSC format (e.g. HDFC0001234)';
  }
  return null;
}

/// Basic account number validation (only structure, not checksum).
String? validateAccountNumber(String? v) {
  if (v == null || v.trim().isEmpty) return 'Account number is required';
  if (v.trim().length < 6) return 'Account number too short';
  if (v.trim().length > 50) return 'Account number too long';
  if (!RegExp(r'^[0-9]+$').hasMatch(v.trim())) {
    return 'Account number must contain only digits';
  }
  return null;
}
