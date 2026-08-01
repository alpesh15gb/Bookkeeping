library;

import 'package:flutter/foundation.dart';

@immutable
class ImportStatementCommand {
  const ImportStatementCommand({
    required this.companyId,
    required this.bankAccountId,
    required this.statementDate,
    required this.openingBalance,
    required this.closingBalance,
    required this.lines,
  });
  final String companyId;
  final String bankAccountId;
  final String statementDate;
  final String openingBalance;
  final String closingBalance;
  final List<StatementLineCommand> lines;
}

@immutable
class StatementLineCommand {
  const StatementLineCommand({
    required this.transactionDate,
    required this.amountPaise,
    required this.balancePaise,
    this.description,
    this.referenceNumber,
    this.externalId,
  });
  final String transactionDate;
  final String? description;
  final String? referenceNumber;
  final int amountPaise;
  final int balancePaise;
  final String? externalId;
}

@immutable
class MatchStatementLineCommand {
  const MatchStatementLineCommand({
    required this.companyId,
    required this.statementLineLocalId,
    required this.sourceType,
    required this.sourceLocalId,
    required this.matchedAmountPaise,
  });
  final String companyId;
  final String statementLineLocalId;
  final String sourceType;
  final String sourceLocalId;
  final int matchedAmountPaise;
}

@immutable
class FinalizeReconciliationCommand {
  const FinalizeReconciliationCommand({
    required this.companyId,
    required this.statementId,
    required this.reconciliationDate,
    required this.openingBalancePaise,
    required this.closingBalancePaise,
    required this.bankAccountId,
  });
  final String companyId;
  final String statementId;
  final String reconciliationDate;
  final int openingBalancePaise;
  final int closingBalancePaise;
  final String bankAccountId;
}
