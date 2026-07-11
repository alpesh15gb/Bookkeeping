/// Year-end dashboard and opening balance snapshot models.
library;

import 'package:flutter/foundation.dart';
import 'financial_year.dart';

/// Year-end closing readiness dashboard.
@immutable
class YearEndDashboard {
  const YearEndDashboard({
    this.financialYear,
    this.readinessScore = 0,
    this.trialBalanceBalanced = false,
    this.unpostedDocumentsCount = 0,
    this.unpostedDocuments = const [],
    this.netProfit = 0,
    this.closingAllowed = false,
    this.blockingItems = const [],
  });

  final FinancialYear? financialYear;
  final int readinessScore;
  final bool trialBalanceBalanced;
  final int unpostedDocumentsCount;
  final List<UnpostedDocument> unpostedDocuments;
  final double netProfit;
  final bool closingAllowed;
  final List<String> blockingItems;

  factory YearEndDashboard.fromJson(
    Map<String, dynamic> json,
  ) => YearEndDashboard(
    financialYear: json['financial_year'] != null
        ? FinancialYear.fromJson(json['financial_year'] as Map<String, dynamic>)
        : null,
    readinessScore: json['readiness_score'] as int? ?? 0,
    trialBalanceBalanced: json['trial_balance_balanced'] as bool? ?? false,
    unpostedDocumentsCount: json['unposted_documents_count'] as int? ?? 0,
    unpostedDocuments:
        (json['unposted_documents'] as List?)
            ?.map((e) => UnpostedDocument.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    netProfit: _num(json['net_profit']),
    closingAllowed: json['closing_allowed'] as bool? ?? false,
    blockingItems:
        (json['blocking_items'] as List?)?.map((e) => e.toString()).toList() ??
        [],
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// A document that hasn't been posted (blocks year-end close).
@immutable
class UnpostedDocument {
  const UnpostedDocument({
    this.id = '',
    this.documentType = '',
    this.documentNumber = '',
    this.date = '',
    this.amount = 0,
  });

  final String id;
  final String documentType;
  final String documentNumber;
  final String date;
  final double amount;

  factory UnpostedDocument.fromJson(Map<String, dynamic> json) =>
      UnpostedDocument(
        id: (json['id'] ?? '').toString(),
        documentType: json['document_type'] as String? ?? '',
        documentNumber: json['document_number'] as String? ?? '',
        date: json['date'] as String? ?? '',
        amount: _num(json['amount']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// Opening balance carried forward from a previous financial year.
@immutable
class OpeningBalanceSnapshot {
  const OpeningBalanceSnapshot({
    this.id = '',
    this.accountId = '',
    this.accountType = '',
    this.accountName = '',
    this.accountCode = '',
    this.closingBalance = 0,
    this.direction = '',
    this.createdAt,
  });

  final String id;
  final String accountId;
  final String accountType;
  final String accountName;
  final String accountCode;
  final double closingBalance;
  final String direction;
  final String? createdAt;

  factory OpeningBalanceSnapshot.fromJson(Map<String, dynamic> json) =>
      OpeningBalanceSnapshot(
        id: (json['id'] ?? '').toString(),
        accountId: (json['account_id'] ?? '').toString(),
        accountType: json['account_type'] as String? ?? '',
        accountName: json['account_name'] as String? ?? '',
        accountCode: json['account_code'] as String? ?? '',
        closingBalance: _num(json['closing_balance']),
        direction: json['direction'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// Inventory carry-forward snapshot.
@immutable
class InventoryCarryForward {
  const InventoryCarryForward({
    this.id = '',
    this.productId = '',
    this.productName = '',
    this.productSku = '',
    this.closingQuantity = 0,
    this.closingValue = 0,
    this.unitRate = 0,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String productSku;
  final double closingQuantity;
  final double closingValue;
  final double unitRate;
  final String? createdAt;

  factory InventoryCarryForward.fromJson(Map<String, dynamic> json) =>
      InventoryCarryForward(
        id: (json['id'] ?? '').toString(),
        productId: (json['product_id'] ?? '').toString(),
        productName: json['product_name'] as String? ?? '',
        productSku: json['product_sku'] as String? ?? '',
        closingQuantity: _num(json['closing_quantity']),
        closingValue: _num(json['closing_value']),
        unitRate: _num(json['unit_rate']),
        createdAt: json['created_at'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
