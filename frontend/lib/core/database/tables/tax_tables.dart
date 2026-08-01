library;

import 'package:drift/drift.dart';

class TaxCodes extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get name => text()();
  TextColumn get rate => text()();
  TextColumn get taxType => text()(); // 'IGST', 'CGST', 'SGST', 'CESS', 'NONE'
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {localId};
}

class TaxPeriods extends Table {
  TextColumn get localId => text()();
  TextColumn get companyId => text()();
  TextColumn get periodName => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {localId};
}

class TaxReturns extends Table {
  TextColumn get localId => text()();
  TextColumn get companyId => text()();
  TextColumn get periodId => text()();
  TextColumn get returnType => text()(); // 'GST', 'SALES_TAX', etc.
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('draft'))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncError => text().nullable()();
  @override
  Set<Column> get primaryKey => {localId};
}

class TaxReturnLines extends Table {
  TextColumn get localId => text()();
  TextColumn get returnId => text()();
  TextColumn get sourceType => text()(); // 'invoice', 'credit_note', etc.
  TextColumn get sourceLocalId => text()();
  TextColumn get taxCode => text()();
  IntColumn get taxableAmountPaise => integer()();
  IntColumn get taxAmountPaise => integer()();
  @override
  Set<Column> get primaryKey => {localId};
}
