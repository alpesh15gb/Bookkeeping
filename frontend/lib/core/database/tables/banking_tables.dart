/// Drift tables for bank accounts, statements, and reconciliation.
library;

import 'package:drift/drift.dart';

class BankAccounts extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get accountName => text()();
  TextColumn get accountNumber => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get ifscCode => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {localId};
}

class BankStatements extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get bankAccountId => text()();
  TextColumn get statementDate => text()();
  TextColumn get openingBalance => text()();
  TextColumn get closingBalance => text()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {localId};
}

class BankStatementLines extends Table {
  TextColumn get localId => text()();
  TextColumn get statementId => text()();
  TextColumn get transactionDate => text()();
  TextColumn get description => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  IntColumn get amountPaise => integer()();
  IntColumn get balancePaise => integer()();
  BoolColumn get isMatched => boolean().withDefault(const Constant(false))();
  TextColumn get matchLocalId => text().nullable()();
  TextColumn get externalId => text().nullable()();
  @override
  Set<Column> get primaryKey => {localId};
}

class BankMatches extends Table {
  TextColumn get localId => text()();
  TextColumn get companyId => text()();
  TextColumn get statementLineLocalId => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceLocalId => text()();
  IntColumn get matchedAmountPaise => integer()();
  BoolColumn get isReconciled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {localId};
}

class BankReconciliations extends Table {
  TextColumn get localId => text()();
  TextColumn get companyId => text()();
  TextColumn get bankAccountId => text()();
  TextColumn get statementId => text()();
  TextColumn get reconciliationDate => text()();
  IntColumn get openingBalancePaise => integer()();
  IntColumn get closingBalancePaise => integer()();
  IntColumn get statementTotalPaise => integer()();
  BoolColumn get isFinalized => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {localId};
}
