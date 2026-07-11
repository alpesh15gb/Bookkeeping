/// Bank reconciliation models.
library;

import 'package:flutter/foundation.dart';

/// A bank statement transaction (imported or manually entered).
@immutable
class BankTransaction {
  const BankTransaction({
    this.id = '',
    this.transactionDate = '',
    this.description = '',
    this.referenceNumber = '',
    this.debitAmount = 0,
    this.creditAmount = 0,
    this.balance = 0,
    this.isReconciled = false,
    this.reconciledAt,
  });

  final String id;
  final String transactionDate;
  final String description;
  final String referenceNumber;
  final double debitAmount;
  final double creditAmount;
  final double balance;
  final bool isReconciled;
  final String? reconciledAt;

  factory BankTransaction.fromJson(Map<String, dynamic> json) =>
      BankTransaction(
        id: (json['id'] ?? '').toString(),
        transactionDate: json['transaction_date'] as String? ?? '',
        description: json['description'] as String? ?? '',
        referenceNumber: json['reference_number'] as String? ?? '',
        debitAmount: _num(json['debit_amount']),
        creditAmount: _num(json['credit_amount']),
        balance: _num(json['balance']),
        isReconciled: json['is_reconciled'] as bool? ?? false,
        reconciledAt: json['reconciled_at'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// A single matched pair (bank transaction ↔ journal entry).
@immutable
class ReconciliationMatch {
  const ReconciliationMatch({
    this.bankTransactionId = '',
    this.journalEntryId = '',
    this.matchedAmount = 0,
  });

  final String bankTransactionId;
  final String journalEntryId;
  final double matchedAmount;

  factory ReconciliationMatch.fromJson(Map<String, dynamic> json) =>
      ReconciliationMatch(
        bankTransactionId: (json['bank_transaction_id'] ?? '').toString(),
        journalEntryId: (json['journal_entry_id'] ?? '').toString(),
        matchedAmount: _num(json['matched_amount']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// A single bank reconciliation record.
@immutable
class BankReconciliation {
  const BankReconciliation({
    this.id = '',
    this.bankingProfileId = '',
    this.bankingProfileName = '',
    this.statementDate = '',
    this.closingBalance = 0,
    this.statementBalance = 0,
    this.difference = 0,
    this.status = '',
    this.transactions = const [],
    this.matches = const [],
    this.createdAt,
  });

  final String id;
  final String bankingProfileId;
  final String bankingProfileName;
  final String statementDate;
  final double closingBalance;
  final double statementBalance;
  final double difference;
  final String status;
  final List<BankTransaction> transactions;
  final List<ReconciliationMatch> matches;
  final String? createdAt;

  bool get isBalanced => difference.abs() < 0.01;

  factory BankReconciliation.fromJson(Map<String, dynamic> json) =>
      BankReconciliation(
        id: (json['id'] ?? '').toString(),
        bankingProfileId: (json['banking_profile_id'] ?? '').toString(),
        bankingProfileName: json['banking_profile_name'] as String? ?? '',
        statementDate: json['statement_date'] as String? ?? '',
        closingBalance: _num(json['closing_balance']),
        statementBalance: _num(json['statement_balance']),
        difference: _num(json['difference']),
        status: json['status'] as String? ?? '',
        transactions:
            (json['transactions'] as List?)
                ?.map(
                  (e) => BankTransaction.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        matches:
            (json['matches'] as List?)
                ?.map(
                  (e) =>
                      ReconciliationMatch.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        createdAt: json['created_at'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// List item for bank reconciliations index.
@immutable
class BankReconciliationListItem {
  const BankReconciliationListItem({
    this.id = '',
    this.bankingProfileName = '',
    this.statementDate = '',
    this.closingBalance = 0,
    this.difference = 0,
    this.status = '',
    this.createdAt,
  });

  final String id;
  final String bankingProfileName;
  final String statementDate;
  final double closingBalance;
  final double difference;
  final String status;
  final String? createdAt;

  factory BankReconciliationListItem.fromJson(Map<String, dynamic> json) =>
      BankReconciliationListItem(
        id: (json['id'] ?? '').toString(),
        bankingProfileName: json['banking_profile_name'] as String? ?? '',
        statementDate: json['statement_date'] as String? ?? '',
        closingBalance: _num(json['closing_balance']),
        difference: _num(json['difference']),
        status: json['status'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
