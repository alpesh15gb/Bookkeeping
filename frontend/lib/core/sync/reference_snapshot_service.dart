/// Hydrates the native offline database from the server's authoritative
/// reference-data snapshot.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../utils/money.dart';

class ReferenceSnapshotService {
  const ReferenceSnapshotService({required AppDatabase db, required Dio dio})
    : _db = db,
      _dio = dio;

  final AppDatabase _db;
  final Dio _dio;

  /// Returns false when the server is unreachable. Existing local reference
  /// data remains usable, which is the expected offline-start behaviour.
  Future<bool> refresh() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/apexbooks/reference-snapshot',
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final body = response.data;
      if (body == null) return false;
      final companyId = body['company_id']?.toString() ?? '';
      if (companyId.isEmpty) return false;
      final now = DateTime.now().toUtc();

      await _db.transaction(() async {
        await _db
            .into(_db.companyProfiles)
            .insertOnConflictUpdate(
              CompanyProfilesCompanion(
                companyId: Value(companyId),
                originStateCode: Value(
                  _nullableString(body['origin_state_code']),
                ),
                lastSyncedAt: Value(now),
              ),
            );
        for (final raw in body['accounts'] as List? ?? const []) {
          final account = Map<String, dynamic>.from(raw as Map);
          final id = account['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          await _db
              .into(_db.accounts)
              .insertOnConflictUpdate(
                AccountsCompanion(
                  localId: Value(id),
                  remoteId: Value(id),
                  companyId: Value(companyId),
                  code: Value(account['code']?.toString() ?? ''),
                  name: Value(account['name']?.toString() ?? ''),
                  accountType: Value(
                    (account['account_type']?.toString() ?? '').toLowerCase(),
                  ),
                  parentRemoteId: Value(_nullableString(account['parent_id'])),
                  accountGroup: Value(
                    _nullableString(account['account_group']),
                  ),
                  isActive: Value(account['is_active'] as bool? ?? true),
                  openingBalancePaise: Value(
                    _rupeesToPaise(account['opening_balance']),
                  ),
                  syncStatus: const Value('synced'),
                  lastSyncedAt: Value(now),
                  updatedAt: Value(_date(account['updated_at'], now)),
                ),
              );
        }

        for (final raw in body['contacts'] as List? ?? const []) {
          final contact = Map<String, dynamic>.from(raw as Map);
          final id = contact['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          await _db
              .into(_db.contacts)
              .insertOnConflictUpdate(
                ContactsCompanion(
                  localId: Value(id),
                  remoteId: Value(id),
                  companyId: Value(companyId),
                  name: Value(contact['name']?.toString() ?? ''),
                  email: Value(_nullableString(contact['email'])),
                  phone: Value(_nullableString(contact['phone'])),
                  contactType: Value(
                    _contactType(contact['contact_type']?.toString()),
                  ),
                  gstin: Value(_nullableString(contact['gstin'])),
                  stateCode: Value(_nullableString(contact['state_code'])),
                  receivableAccountId: Value(
                    _nullableString(contact['receivable_account_id']),
                  ),
                  payableAccountId: Value(
                    _nullableString(contact['payable_account_id']),
                  ),
                  isActive: Value(contact['is_active'] as bool? ?? true),
                  openingBalancePaise: Value(
                    _rupeesToPaise(contact['opening_balance']),
                  ),
                  syncStatus: const Value('synced'),
                  lastSyncedAt: Value(now),
                  updatedAt: Value(_date(contact['updated_at'], now)),
                ),
              );
        }

        for (final raw in body['products'] as List? ?? const []) {
          final product = Map<String, dynamic>.from(raw as Map);
          final id = product['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          await _db
              .into(_db.stockItems)
              .insertOnConflictUpdate(
                StockItemsCompanion(
                  localId: Value(id),
                  remoteId: Value(id),
                  companyId: Value(companyId),
                  name: Value(product['name']?.toString() ?? ''),
                  sku: Value(_nullableString(product['sku'])),
                  unit: Value(product['uom']?.toString() ?? 'PCS'),
                  hsnSac: Value(_nullableString(product['hsn_sac'])),
                  currentQuantity: Value(
                    product['current_stock']?.toString() ?? '0',
                  ),
                  unitCostPaise: Value(
                    _rupeesToPaise(product['purchase_price']),
                  ),
                  salesPricePaise: Value(
                    _rupeesToPaise(product['sales_price']),
                  ),
                  gstRateBasisPoints: Value(
                    _percentToBasisPoints(product['gst_rate']),
                  ),
                  isActive: Value(product['is_active'] as bool? ?? true),
                  syncStatus: const Value('synced'),
                  createdAt: Value(_date(product['updated_at'], now)),
                  updatedAt: Value(_date(product['updated_at'], now)),
                ),
              );
        }
      });
      return true;
    } on DioException {
      return false;
    }
  }
}

String? _nullableString(Object? value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

DateTime _date(Object? value, DateTime fallback) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc() ?? fallback;

int _rupeesToPaise(Object? value) {
  final amount = double.tryParse(value?.toString() ?? '') ?? 0;
  return Money.fromRupees(amount).toPaise();
}

int _percentToBasisPoints(Object? value) =>
    ((double.tryParse(value?.toString() ?? '') ?? 0) * 100).round();

String _contactType(String? value) => switch (value?.toUpperCase()) {
  'CUSTOMER' => 'customer',
  'VENDOR' => 'vendor',
  _ => 'both',
};
