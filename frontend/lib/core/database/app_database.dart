/// AppDatabase — the central Drift database for ApexBooks.
///
/// This is the **single source of truth** for all local data.  Every read
/// and write in the application goes through this database; remote APIs are
/// only used by the sync engine running in the background.
///
/// ## Adding new tables
/// 1. Define the table in `tables/`.
/// 2. Add it to the `@DriftDatabase(tables: [...])` annotation below.
/// 3. Add a migration step in `migrations/`.
/// 4. Run `flutter pub run build_runner build` to regenerate `app_database.g.dart`.
///
/// ## Encryption
/// Database creation is isolated in [AppDatabase.connect] so an encrypted
/// executor can be substituted in the future without touching any repository.
library;

import 'package:drift/drift.dart';
import 'native_database_encryption.dart';

import 'tables/sync_tables.dart';
import 'tables/journal_tables.dart';
import 'tables/reference_tables.dart';
import 'tables/invoice_tables.dart';
import 'tables/payment_tables.dart';
import 'tables/inventory_tables.dart';
import 'tables/purchasing_tables.dart';
import 'tables/sales_tables.dart';
import 'tables/returns_tables.dart';
import 'tables/credit_debit_tables.dart';
import 'tables/banking_tables.dart';
import 'tables/tax_tables.dart';
import 'tables/assets_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    // Sync infrastructure
    SyncOperations,
    SyncConflicts,
    SyncCheckpoints,
    // Accounting — journals
    JournalEntries,
    JournalLines,
    // Reference data (pulled)
    CompanyProfiles,
    Accounts,
    Contacts,
    // Invoices + numbering
    NumberAllocations,
    Invoices,
    InvoiceLines,
    InvoiceTaxLines,
    // Payments
    Payments,
    PaymentAllocations,
    // Inventory
    StockItems,
    InventoryMovements,
    InventoryBalances,
    // Purchasing
    PurchaseOrders,
    PurchaseOrderLines,
    PurchaseReceipts,
    PurchaseReceiptLines,
    PurchaseInvoices,
    PurchaseInvoiceLines,
    // Sales fulfilment
    SalesOrders,
    SalesOrderLines,
    SalesDeliveries,
    SalesDeliveryLines,
    // Returns
    SalesReturns,
    SalesReturnLines,
    PurchaseReturns,
    PurchaseReturnLines,
    // Credit/Debit notes
    CreditNotes,
    CreditNoteLines,
    CreditNoteTaxLines,
    DebitNotes,
    DebitNoteLines,
    DebitNoteTaxLines,
    // Banking
    BankAccounts,
    BankStatements,
    BankStatementLines,
    BankMatches,
    BankReconciliations,
    // Tax
    TaxCodes,
    TaxPeriods,
    TaxReturns,
    TaxReturnLines,
    // Fixed assets
    FixedAssets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.encrypted(String key) : super(openEncryptedNativeDatabase(key));

  @override
  int get schemaVersion => 17;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 1) {
        // v0 → v1 : no-op — fresh DB from first release.
      }
      if (from < 2) {
        // v1 → v2: add execution-context columns to sync_operations.
        await customStatement(
          'ALTER TABLE sync_operations ADD COLUMN company_id TEXT NOT NULL DEFAULT \'\'',
        );
        await customStatement(
          'ALTER TABLE sync_operations ADD COLUMN financial_year_id TEXT',
        );
        await customStatement(
          'ALTER TABLE sync_operations ADD COLUMN actor_id TEXT NOT NULL DEFAULT \'\'',
        );
        await customStatement(
          'ALTER TABLE sync_operations ADD COLUMN device_id TEXT NOT NULL DEFAULT \'\'',
        );
        await customStatement(
          'ALTER TABLE journal_entries ADD COLUMN lifecycle_status TEXT NOT NULL DEFAULT \'draft\'',
        );
        await customStatement(
          'UPDATE journal_entries SET lifecycle_status = '
          'CASE status '
          'WHEN \'DRAFT\' THEN \'draft\' '
          'WHEN \'POSTED\' THEN \'posted\' '
          'ELSE \'draft\' END',
        );
      }
      if (from < 3) {
        await m.createAll();
      }
      // v3 → v4: add invoice + number-allocation tables.
      if (from < 4) {
        await m.createAll();
      }
      // v4 → v5: add payment tables.
      if (from < 5) {
        await m.createAll();
      }
      // v5 → v6: add inventory tables.
      if (from < 6) {
        await m.createAll();
      }
      // v6 → v7: add purchasing tables.
      if (from < 7) {
        await m.createAll();
      }
      // v7 → v8: add sales fulfilment tables.
      if (from < 8) {
        await m.createAll();
      }
      // v8 → v9: add returns tables.
      if (from < 9) {
        await m.createAll();
      }
      // v9 → v10: add credit/debit note tables.
      if (from < 10) {
        await m.createAll();
      }
      // v10 → v11: add banking tables.
      if (from < 11) {
        await m.createAll();
      }
      // v11 → v12: add tax tables.
      if (from < 12) {
        await m.createAll();
      }
      // v12 → v13: add fixed assets tables.
      if (from < 13) {
        await m.createAll();
      }
      // v13 → v14: persist formatting metadata for offline number leases.
      if (from >= 4 && from < 14) {
        await m.addColumn(numberAllocations, numberAllocations.prefix);
        await m.addColumn(numberAllocations, numberAllocations.suffix);
        await m.addColumn(numberAllocations, numberAllocations.paddingDigits);
        await m.addColumn(invoices, invoices.displayNumber);
      }
      // v14 → v15: server-provisioned control accounts and product pricing
      // are required for correct offline financial posting.
      if (from >= 13 && from < 15) {
        await m.addColumn(contacts, contacts.receivableAccountId);
        await m.addColumn(contacts, contacts.payableAccountId);
        await m.addColumn(stockItems, stockItems.hsnSac);
        await m.addColumn(stockItems, stockItems.salesPricePaise);
        await m.addColumn(stockItems, stockItems.gstRateBasisPoints);
      }
      // v15 → v16: preserve line-level tax rates used for legal totals.
      if (from >= 4 && from < 16) {
        await m.addColumn(invoiceLines, invoiceLines.taxRateBasisPoints);
        await m.addColumn(invoiceLines, invoiceLines.taxPaise);
      }
      if (from >= 13 && from < 17) {
        await m.createTable(companyProfiles);
      }
    },
    beforeOpen: (details) async {
      // Enable WAL mode for better concurrent read performance.
      await customStatement('PRAGMA journal_mode=WAL;');
      // Enforce FK constraints.
      await customStatement('PRAGMA foreign_keys=ON;');
    },
  );

  // ── Convenience query helpers ─────────────────────────────────────────────

  // ---- Sync operations ----

  Future<List<SyncOperation>> pendingOperations({
    int limit = 50,
    String? companyId,
  }) {
    final now = DateTime.now().toUtc();
    return (select(syncOperations)
          ..where((o) {
            var condition =
                o.status.equals('pending') &
                (o.nextAttemptAt.isNull() |
                    o.nextAttemptAt.isSmallerOrEqualValue(now));
            if (companyId != null) {
              condition = condition & o.companyId.equals(companyId);
            }
            return condition;
          })
          ..orderBy([
            (o) => OrderingTerm.asc(o.priority),
            (o) => OrderingTerm.asc(o.createdAt),
          ])
          ..limit(limit))
        .get();
  }

  /// Removes only terminal sync history older than [retention].
  ///
  /// Pending, failed, syncing, and unresolved-conflict rows are retained so
  /// cleanup cannot discard queued work or hide an actionable problem.
  Future<int> pruneSyncHistory({
    DateTime? now,
    Duration retention = const Duration(days: 30),
  }) async {
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc().subtract(retention);
    return transaction(() async {
      final operationsDeleted =
          await (delete(syncOperations)..where(
                (operation) =>
                    operation.status.equals('synced') &
                    operation.completedAt.isNotNull() &
                    operation.completedAt.isSmallerThanValue(cutoff),
              ))
              .go();
      final conflictsDeleted =
          await (delete(syncConflicts)..where(
                (conflict) =>
                    conflict.resolution.isNotNull() &
                    conflict.resolvedAt.isNotNull() &
                    conflict.resolvedAt.isSmallerThanValue(cutoff),
              ))
              .go();
      return operationsDeleted + conflictsDeleted;
    });
  }

  // ── Static factory ────────────────────────────────────────────────────────

  /// Opens (or creates) the database file appropriate for the current platform.
  ///
  /// Isolate this call behind this factory so encryption can be added later
  /// by swapping the executor without touching any other code.
}
