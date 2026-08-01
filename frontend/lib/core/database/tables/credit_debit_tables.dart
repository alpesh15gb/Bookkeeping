/// Drift tables for credit notes and debit notes.
library;

import 'package:drift/drift.dart';

class CreditNotes extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get creditNoteDate => text()();
  TextColumn get customerId => text()();
  TextColumn get customerName => text()();
  TextColumn get sourceInvoiceLocalId => text().nullable()();
  TextColumn get salesReturnLocalId => text().nullable()();
  IntColumn get number => integer().nullable()();
  TextColumn get allocationId => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get totalBeforeTaxPaise => integer()();
  IntColumn get taxPaise => integer()();
  IntColumn get totalPaise => integer()();
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('draft'))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get syncError => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  TextColumn get originDeviceId => text()();
  @override
  Set<Column> get primaryKey => {localId};
}

class CreditNoteLines extends Table {
  TextColumn get localId => text()();
  TextColumn get creditNoteLocalId => text()();
  TextColumn get sourceInvoiceLineLocalId => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  TextColumn get quantity => text()();
  IntColumn get unitPricePaise => integer()();
  IntColumn get totalPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}

class CreditNoteTaxLines extends Table {
  TextColumn get localId => text()();
  TextColumn get creditNoteLocalId => text()();
  TextColumn get taxType => text()();
  TextColumn get taxRate => text()();
  IntColumn get taxAmountPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}

class DebitNotes extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get debitNoteDate => text()();
  TextColumn get supplierId => text()();
  TextColumn get supplierName => text()();
  TextColumn get sourceInvoiceLocalId => text().nullable()();
  TextColumn get purchaseReturnLocalId => text().nullable()();
  IntColumn get number => integer().nullable()();
  TextColumn get allocationId => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get totalBeforeTaxPaise => integer()();
  IntColumn get taxPaise => integer()();
  IntColumn get totalPaise => integer()();
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('draft'))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get syncError => text().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  TextColumn get originDeviceId => text()();
  @override
  Set<Column> get primaryKey => {localId};
}

class DebitNoteLines extends Table {
  TextColumn get localId => text()();
  TextColumn get debitNoteLocalId => text()();
  TextColumn get sourceInvoiceLineLocalId => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  TextColumn get quantity => text()();
  IntColumn get unitPricePaise => integer()();
  IntColumn get totalPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}

class DebitNoteTaxLines extends Table {
  TextColumn get localId => text()();
  TextColumn get debitNoteLocalId => text()();
  TextColumn get taxType => text()();
  TextColumn get taxRate => text()();
  IntColumn get taxAmountPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}
