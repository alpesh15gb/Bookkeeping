library;

import 'package:drift/drift.dart';

class FixedAssets extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  IntColumn get purchaseCostPaise => integer()();
  TextColumn get purchaseDate => text()();
  IntColumn get salvageValuePaise => integer().withDefault(const Constant(0))();
  IntColumn get usefulLifeMonths => integer()();
  TextColumn get depreciationMethod =>
      text().withDefault(const Constant('straight_line'))();
  IntColumn get accumulatedDepreciationPaise =>
      integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {localId};
}
