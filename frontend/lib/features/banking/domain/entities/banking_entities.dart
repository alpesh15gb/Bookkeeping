library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';

@immutable
class BankAccountEntity {
  const BankAccountEntity({
    required this.localId,
    required this.companyId,
    required this.accountName,
    this.accountNumber,
    this.bankName,
    this.ifscCode,
  });
  final String localId;
  final String companyId;
  final String accountName;
  final String? accountNumber;
  final String? bankName;
  final String? ifscCode;
}

@immutable
class BankStatementEntity {
  const BankStatementEntity({
    required this.localId,
    required this.companyId,
    required this.bankAccountId,
    required this.statementDate,
    required this.openingBalance,
    required this.closingBalance,
    this.syncStatus = SyncStatus.localOnly,
    this.lines = const [],
  });
  final String localId;
  final String companyId;
  final String bankAccountId;
  final String statementDate;
  final String openingBalance;
  final String closingBalance;
  final SyncStatus syncStatus;
  final List<BankStatementLineEntity> lines;
}

@immutable
class BankStatementLineEntity {
  const BankStatementLineEntity({
    required this.localId,
    required this.statementId,
    required this.transactionDate,
    required this.amountPaise,
    required this.balancePaise,
    this.description,
    this.referenceNumber,
    this.isMatched = false,
    this.externalId,
  });
  final String localId;
  final String statementId;
  final String transactionDate;
  final String? description;
  final String? referenceNumber;
  final int amountPaise;
  final int balancePaise;
  final bool isMatched;
  final String? externalId;
}

@immutable
class BankMatchEntity {
  const BankMatchEntity({
    required this.localId,
    required this.companyId,
    required this.statementLineLocalId,
    required this.sourceType,
    required this.sourceLocalId,
    required this.matchedAmountPaise,
  });
  final String localId;
  final String companyId;
  final String statementLineLocalId;
  final String sourceType;
  final String sourceLocalId;
  final int matchedAmountPaise;
}

@immutable
class ReconciliationEntity {
  const ReconciliationEntity({
    required this.localId,
    required this.companyId,
    required this.bankAccountId,
    required this.statementId,
    required this.reconciliationDate,
    required this.isFinalized,
  });
  final String localId;
  final String companyId;
  final String bankAccountId;
  final String statementId;
  final String reconciliationDate;
  final bool isFinalized;
}
