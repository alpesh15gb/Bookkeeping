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

  factory BankTransaction.fromJson(Map<String, dynamic> json) {
    final signedAmount = json.containsKey('amount')
        ? _num(json['amount'])
        : null;

    return BankTransaction(
      id: (json['id'] ?? '').toString(),
      transactionDate: json['transaction_date'] as String? ?? '',
      description: json['description'] as String? ?? '',
      referenceNumber: json['reference_number'] as String? ?? '',
      debitAmount: signedAmount == null
          ? _num(json['debit_amount'])
          : signedAmount < 0
          ? signedAmount.abs()
          : 0,
      creditAmount: signedAmount == null
          ? _num(json['credit_amount'])
          : signedAmount > 0
          ? signedAmount
          : 0,
      balance: _num(json['balance']),
      isReconciled: json['is_reconciled'] as bool? ?? false,
      reconciledAt: json['reconciled_at'] as String?,
    );
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0;
    return 0;
  }
}

/// A backend-generated candidate that can be matched to a bank transaction.
@immutable
class SuggestedMatch {
  const SuggestedMatch({
    this.type = '',
    this.id = '',
    this.amount = '0',
    this.date = '',
    this.reference,
    this.contactName,
    this.score = 0,
  });

  final String type;
  final String id;
  final String amount;
  final String date;
  final String? reference;
  final String? contactName;
  final int score;

  String get confidenceLabel {
    if (score >= 90) return 'High';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Low';
  }

  factory SuggestedMatch.fromJson(Map<String, dynamic> json) => SuggestedMatch(
    type: json['type'] as String? ?? '',
    id: (json['id'] ?? '').toString(),
    amount: (json['amount'] ?? '0').toString(),
    date: json['date'] as String? ?? '',
    reference: json['reference'] as String?,
    contactName: json['contact_name'] as String?,
    score: _int(json['score']),
  );

  static int _int(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// Candidate matches grouped by bank transaction.
@immutable
class MatchSuggestion {
  const MatchSuggestion({
    this.transactionId = '',
    this.transactionDate = '',
    this.transactionAmount = '0',
    this.transactionDescription,
    this.suggestedMatches = const [],
  });

  final String transactionId;
  final String transactionDate;
  final String transactionAmount;
  final String? transactionDescription;
  final List<SuggestedMatch> suggestedMatches;

  factory MatchSuggestion.fromJson(Map<String, dynamic> json) =>
      MatchSuggestion(
        transactionId: (json['transaction_id'] ?? '').toString(),
        transactionDate: json['transaction_date'] as String? ?? '',
        transactionAmount: (json['transaction_amount'] ?? '0').toString(),
        transactionDescription: json['transaction_description'] as String?,
        suggestedMatches:
            (json['suggested_matches'] as List?)
                ?.map((e) => SuggestedMatch.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

enum MatchAction { none, match, categorize, exclude }

/// A user-selected reconciliation decision pending commit.
@immutable
class PendingMatch {
  const PendingMatch({
    required this.bankTransactionId,
    this.suggestedMatch,
    this.action = MatchAction.none,
    this.categoryAccountId,
    this.notes,
  });

  final String bankTransactionId;
  final SuggestedMatch? suggestedMatch;
  final MatchAction action;
  final String? categoryAccountId;
  final String? notes;

  PendingMatch copyWith({
    String? bankTransactionId,
    SuggestedMatch? suggestedMatch,
    MatchAction? action,
    String? categoryAccountId,
    String? notes,
    bool clearMatch = false,
  }) {
    return PendingMatch(
      bankTransactionId: bankTransactionId ?? this.bankTransactionId,
      suggestedMatch: clearMatch ? null : suggestedMatch ?? this.suggestedMatch,
      action: action ?? this.action,
      categoryAccountId: categoryAccountId ?? this.categoryAccountId,
      notes: notes ?? this.notes,
    );
  }
}

/// Derived reconciliation progress totals used by the detail workflow.
@immutable
class ReconciliationStats {
  const ReconciliationStats({
    this.totalTransactions = 0,
    this.matchedTransactions = 0,
    this.pendingTransactions = 0,
    this.totalCredits = 0,
    this.totalDebits = 0,
    this.difference = 0,
    this.isBalanced = false,
  });

  final int totalTransactions;
  final int matchedTransactions;
  final int pendingTransactions;
  final double totalCredits;
  final double totalDebits;
  final double difference;
  final bool isBalanced;

  double get progress =>
      totalTransactions == 0 ? 0 : matchedTransactions / totalTransactions;

  factory ReconciliationStats.fromReconciliation(BankReconciliation rec) {
    final matchedTransactionIds = rec.matches
        .map((m) => m.bankTransactionId)
        .toSet();
    final matched = rec.transactions
        .where((txn) => matchedTransactionIds.contains(txn.id))
        .length;

    return ReconciliationStats(
      totalTransactions: rec.transactions.length,
      matchedTransactions: matched,
      pendingTransactions: rec.transactions.length - matched,
      totalCredits: rec.transactions.fold<double>(
        0,
        (sum, txn) => sum + txn.creditAmount,
      ),
      totalDebits: rec.transactions.fold<double>(
        0,
        (sum, txn) => sum + txn.debitAmount,
      ),
      difference: rec.difference,
      isBalanced: rec.isBalanced,
    );
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
