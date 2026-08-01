/// Reports service — reads from the local Drift database.
///
/// ## Company scoping
/// Every query is scoped to [companyId], which is the active tenant ID from
/// [authControllerProvider].activeMembership?.tenantId.  The provider
/// [reportsServiceProvider] automatically injects this from the auth controller,
/// so callers do not need to pass it manually — but the constructor requires it
/// explicitly so the service can be constructed in tests with any company ID.
///
/// ## Date format
/// All date parameters must be ISO-8601 'YYYY-MM-DD' strings.
/// SQLite stores all dates as text and uses lexicographic ordering which is
/// correct for this format.
///
/// ## Contact ID semantics
/// [getContacts] returns [ContactSummary.id] which is the Drift `localId`.
/// Invoice queries are compiled against `customerId` which may hold either a
/// localId or a remoteId (the app stores whichever was available at creation
/// time).  This service queries both columns using an OR condition.
///
/// ## Lifecycle status
/// - [Invoices] stores statuses as lowercase: 'draft', 'issued'.
/// - [PurchaseInvoices] stores statuses as uppercase: 'DRAFT', 'POSTED', etc.
/// Both sets are filtered consistently.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/database/database_provider.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import '../models/report_models.dart';

class ReportsService {
  ReportsService(this._db, this._companyId);

  final AppDatabase _db;

  /// Active tenant ID — all queries are scoped to this company.
  final String _companyId;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Sum of all PaymentAllocation amounts for the given invoice/bill localId.
  ///
  /// NOTE: as of 2026-08-01 no write path populates `paymentAllocations`, so
  /// this returns 0 for every row and registers show gross amounts. Populating
  /// allocations when a payment posts is a scoped follow-up (out of the UI
  /// modernization pass) and is tracked as such. Do not replace this helper
  /// with contact-level payment sums unless the product accepts that a single
  /// receipt would overstate payment on each of a contact's invoices.
  Future<int> _allocatedPaise(String invoiceLocalId) async {
    final allocs = await (_db.select(_db.paymentAllocations)
          ..where((a) => a.invoiceLocalId.equals(invoiceLocalId)))
        .get();
    return allocs.fold<int>(0, (sum, a) => sum + a.allocatedPaise);
  }

  // ── Sales Register ───────────────────────────────────────────────────────────

  /// Issued sales invoices for the active company within the optional date range.
  Future<Result<List<SalesTransaction>>> getSalesTransactions({
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final query = _db.select(_db.invoices)
        ..where(
          (i) =>
              i.companyId.equals(_companyId) &
              i.deletedAt.isNull() &
              i.lifecycleStatus.equals('issued'),
        );
      if (dateFrom != null) {
        query.where((i) => i.invoiceDate.isBiggerOrEqualValue(dateFrom));
      }
      if (dateTo != null) {
        query.where((i) => i.invoiceDate.isSmallerOrEqualValue(dateTo));
      }
      query.orderBy([
        (i) => OrderingTerm.asc(i.invoiceDate),
        (i) => OrderingTerm.asc(i.number),
      ]);

      final rows = await query.get();
      final items = <SalesTransaction>[];
      for (final r in rows) {
        final paidPaise = await _allocatedPaise(r.localId);
        items.add(SalesTransaction(
          id: r.localId,
          invoiceNumber: r.displayNumber ?? r.number.toString(),
          issueDate: r.invoiceDate,
          customerName: r.customerName,
          subtotal: r.totalBeforeTaxPaise / 100.0,
          taxTotal: r.taxPaise / 100.0,
          total: r.totalPaise / 100.0,
          amountPaid: paidPaise / 100.0,
          status: r.lifecycleStatus.toUpperCase(),
        ));
      }
      return Success(items);
    } catch (e) {
      return Failure(ApiError(message:'Local reports error: $e'));
    }
  }

  // ── Purchase Register ────────────────────────────────────────────────────────

  /// Non-draft, non-cancelled bills for the active company with optional filters.
  Future<Result<List<PurchaseTransaction>>> getBills({
    String? dateFrom,
    String? dateTo,
    String? contactId,
  }) async {
    try {
      final query = _db.select(_db.purchaseInvoices)
        ..where(
          (i) =>
              i.companyId.equals(_companyId) &
              i.deletedAt.isNull() &
              i.lifecycleStatus.isNotIn(['DRAFT', 'CANCELLED']),
        );
      if (dateFrom != null) {
        query.where((i) => i.invoiceDate.isBiggerOrEqualValue(dateFrom));
      }
      if (dateTo != null) {
        query.where((i) => i.invoiceDate.isSmallerOrEqualValue(dateTo));
      }
      if (contactId != null) {
        // supplierId may hold localId or remoteId — check both.
        final contact = await (_db.select(_db.contacts)
              ..where(
                (c) =>
                    c.companyId.equals(_companyId) &
                    (c.localId.equals(contactId) |
                        c.remoteId.equals(contactId)),
              ))
            .getSingleOrNull();
        if (contact != null) {
          query.where(
            (i) =>
                i.supplierId.equals(contact.localId) |
                i.supplierId.equals(contact.remoteId),
          );
        }
      }
      query.orderBy([
        (i) => OrderingTerm.asc(i.invoiceDate),
        (i) => OrderingTerm.asc(i.invoiceNumber),
      ]);

      final rows = await query.get();
      final items = <PurchaseTransaction>[];
      for (final r in rows) {
        final paidPaise = await _allocatedPaise(r.localId);
        items.add(PurchaseTransaction(
          id: r.localId,
          billNumber: r.invoiceNumber,
          issueDate: r.invoiceDate,
          vendorName: r.supplierName,
          total: r.totalPaise / 100.0,
          amountPaid: paidPaise / 100.0,
          status: r.lifecycleStatus,
        ));
      }
      return Success(items);
    } catch (e) {
      return Failure(ApiError(message:'Local reports error: $e'));
    }
  }

  // ── Party Statement ──────────────────────────────────────────────────────────

  /// Running-balance party ledger for [contactId] within [startDate]..[endDate].
  ///
  /// [contactId] is the `localId` value from [ContactSummary.id].
  ///
  /// Opening balance sign convention:
  ///   positive → customer owes us (receivable)
  ///   negative → we owe vendor (payable)
  Future<Result<PartyStatement>> getPartyStatement({
    required String contactId,
    required String startDate,
    required String endDate,
  }) async {
    try {
      // Resolve the contact and collect both localId and remoteId so we can
      // match invoices that stored either value in their customerId/supplierId.
      final contact = await (_db.select(_db.contacts)
            ..where(
              (c) =>
                  c.companyId.equals(_companyId) &
                  (c.localId.equals(contactId) | c.remoteId.equals(contactId)),
            ))
          .getSingleOrNull();
      if (contact == null) {
        return const Failure(ApiError(message: 'Contact not found'));
      }

      final cLocalId = contact.localId;
      final cRemoteId = contact.remoteId;

      // ── Opening balance queries (strictly BEFORE startDate) ─────────────────

      final invoicesBefore = await (_db.select(_db.invoices)
            ..where(
              (i) =>
                  i.companyId.equals(_companyId) &
                  i.deletedAt.isNull() &
                  i.lifecycleStatus.equals('issued') &
                  (i.customerId.equals(cLocalId) |
                      i.customerId.equals(cRemoteId)) &
                  i.invoiceDate.isSmallerThanValue(startDate),
            ))
          .get();

      final paymentsBefore = await (_db.select(_db.payments)
            ..where(
              (p) =>
                  p.companyId.equals(_companyId) &
                  p.deletedAt.isNull() &
                  p.lifecycleStatus.equals('posted') &
                  (p.contactId.equals(cLocalId) |
                      p.contactId.equals(cRemoteId)) &
                  p.paymentDate.isSmallerThanValue(startDate),
            ))
          .get();

      final billsBefore = await (_db.select(_db.purchaseInvoices)
            ..where(
              (b) =>
                  b.companyId.equals(_companyId) &
                  b.deletedAt.isNull() &
                  // Exclude drafts and cancelled bills from opening balance.
                  b.lifecycleStatus.isNotIn(['DRAFT', 'CANCELLED']) &
                  (b.supplierId.equals(cLocalId) |
                      b.supplierId.equals(cRemoteId)) &
                  b.invoiceDate.isSmallerThanValue(startDate),
            ))
          .get();

      double openingBalance = 0;

      for (final inv in invoicesBefore) {
        openingBalance += inv.totalPaise / 100.0; // DR: customer owes us
      }
      for (final bill in billsBefore) {
        openingBalance -= bill.totalPaise / 100.0; // CR: we owe vendor
      }
      for (final pay in paymentsBefore) {
        final amt = pay.amountPaise / 100.0;
        if (pay.paymentType == 'RECEIPT') {
          openingBalance -= amt; // CR: customer paid us → reduces receivable
        } else {
          // PAYMENT (money sent to vendor) → reduces what we owe → increases balance
          openingBalance += amt;
        }
      }

      // ── Period transaction queries ───────────────────────────────────────────

      final invoicesPeriod = await (_db.select(_db.invoices)
            ..where(
              (i) =>
                  i.companyId.equals(_companyId) &
                  i.deletedAt.isNull() &
                  i.lifecycleStatus.equals('issued') &
                  (i.customerId.equals(cLocalId) |
                      i.customerId.equals(cRemoteId)) &
                  i.invoiceDate.isBiggerOrEqualValue(startDate) &
                  i.invoiceDate.isSmallerOrEqualValue(endDate),
            ))
          .get();

      final paymentsPeriod = await (_db.select(_db.payments)
            ..where(
              (p) =>
                  p.companyId.equals(_companyId) &
                  p.deletedAt.isNull() &
                  p.lifecycleStatus.equals('posted') &
                  (p.contactId.equals(cLocalId) |
                      p.contactId.equals(cRemoteId)) &
                  p.paymentDate.isBiggerOrEqualValue(startDate) &
                  p.paymentDate.isSmallerOrEqualValue(endDate),
            ))
          .get();

      final billsPeriod = await (_db.select(_db.purchaseInvoices)
            ..where(
              (b) =>
                  b.companyId.equals(_companyId) &
                  b.deletedAt.isNull() &
                  b.lifecycleStatus.isNotIn(['DRAFT', 'CANCELLED']) &
                  (b.supplierId.equals(cLocalId) |
                      b.supplierId.equals(cRemoteId)) &
                  b.invoiceDate.isBiggerOrEqualValue(startDate) &
                  b.invoiceDate.isSmallerOrEqualValue(endDate),
            ))
          .get();

      // ── Build unsorted row list ─────────────────────────────────────────────

      final unsorted = <PartyStatementRow>[];
      double totalSales = 0;
      double totalReceipts = 0;
      double totalPurchases = 0;
      double totalPayments = 0;

      for (final inv in invoicesPeriod) {
        final amt = inv.totalPaise / 100.0;
        totalSales += amt;
        unsorted.add(PartyStatementRow(
          date: inv.invoiceDate,
          particulars: 'Sales Invoice',
          voucherType: 'INVOICE',
          voucherNo: inv.displayNumber ?? inv.number.toString(),
          debit: amt,
          credit: 0.0,
          createdAt: inv.createdAt.toIso8601String(),
        ));
      }

      for (final bill in billsPeriod) {
        final amt = bill.totalPaise / 100.0;
        totalPurchases += amt;
        unsorted.add(PartyStatementRow(
          date: bill.invoiceDate,
          particulars: 'Purchase Bill',
          voucherType: 'BILL',
          voucherNo: bill.invoiceNumber,
          debit: 0.0,
          credit: amt,
          createdAt: bill.createdAt.toIso8601String(),
        ));
      }

      for (final pay in paymentsPeriod) {
        final amt = pay.amountPaise / 100.0;
        if (pay.paymentType == 'RECEIPT') {
          totalReceipts += amt;
          unsorted.add(PartyStatementRow(
            date: pay.paymentDate,
            particulars: 'Customer Receipt',
            voucherType: 'RECEIPT',
            voucherNo:
                pay.referenceNumber ?? pay.localId.substring(0, 8),
            debit: 0.0,
            credit: amt,
            createdAt: pay.createdAt.toIso8601String(),
          ));
        } else {
          totalPayments += amt;
          unsorted.add(PartyStatementRow(
            date: pay.paymentDate,
            particulars: 'Vendor Payment',
            voucherType: 'PAYMENT',
            voucherNo:
                pay.referenceNumber ?? pay.localId.substring(0, 8),
            debit: amt,
            credit: 0.0,
            createdAt: pay.createdAt.toIso8601String(),
          ));
        }
      }

      // ── Sort: date asc, then createdAt asc for stability ───────────────────

      unsorted.sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        return a.createdAt.compareTo(b.createdAt);
      });

      // ── Compute running balance ─────────────────────────────────────────────

      double runningBalance = openingBalance;
      final statementRows = <PartyStatementRow>[];
      for (final r in unsorted) {
        runningBalance += (r.debit ?? 0.0) - (r.credit ?? 0.0);
        statementRows.add(PartyStatementRow(
          date: r.date,
          particulars: r.particulars,
          voucherType: r.voucherType,
          voucherNo: r.voucherNo,
          debit: (r.debit ?? 0.0) == 0.0 ? null : r.debit,
          credit: (r.credit ?? 0.0) == 0.0 ? null : r.credit,
          balance: runningBalance.toStringAsFixed(2),
        ));
      }

      final summary = PartyStatementSummary(
        openingBalance: openingBalance,
        totalSales: totalSales,
        totalReceipts: totalReceipts,
        totalPurchases: totalPurchases,
        totalPayments: totalPayments,
        closingOutstanding: runningBalance,
      );

      return Success(PartyStatement(
        contactId: contactId,
        contactName: contact.name,
        contactType: contact.contactType,
        address: null, // Contacts table has no billingAddress column.
        gstin: contact.gstin,
        phone: contact.phone,
        startDate: startDate,
        endDate: endDate,
        ledger: statementRows,
        summary: summary,
      ));
    } catch (e) {
      return Failure(ApiError(message:'Local statement error: $e'));
    }
  }

  // ── Contacts autocomplete ────────────────────────────────────────────────────

  /// Active contacts for the active company, optionally filtered by type/name.
  Future<Result<List<ContactSummary>>> getContacts({
    String? contactType,
    String? search,
  }) async {
    try {
      final query = _db.select(_db.contacts)
        ..where(
          (c) =>
              c.companyId.equals(_companyId) & c.isActive.equals(true),
        );
      if (contactType != null) {
        query.where((c) => c.contactType.equals(contactType.toLowerCase()));
      }
      if (search != null && search.isNotEmpty) {
        query.where((c) => c.name.like('%$search%'));
      }
      query.orderBy([(c) => OrderingTerm.asc(c.name)]);

      final rows = await query.get();
      return Success(rows
          .map((r) => ContactSummary(
                id: r.localId,
                name: r.name,
                contactType: r.contactType.toUpperCase(),
              ))
          .toList());
    } catch (e) {
      return Failure(ApiError(message:'Local reports contacts error: $e'));
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides a [ReportsService] scoped to the active company.
///
/// The company ID is derived from [authControllerProvider].activeMembership.
/// When no company is active (e.g. during login) the service uses an empty
/// string, which safely returns empty results from every query.
final reportsServiceProvider = Provider<ReportsService>((ref) {
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return ReportsService(ref.watch(databaseProvider), companyId);
});
