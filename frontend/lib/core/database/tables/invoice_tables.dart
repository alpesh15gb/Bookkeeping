/// Drift table definitions for invoices and number allocation.
library;

import 'package:drift/drift.dart';

// ── Number allocations ─────────────────────────────────────────────────────────

/// Pre-allocated number ranges per (company, device, series, FY).
///
/// Populated by a pull-like mechanism from the backend allocation endpoint.
/// Consumed monotonically — `used` tracks how many numbers from this block
/// have been assigned.
class NumberAllocations extends Table {
  TextColumn get id => text()(); // local UUID

  /// Server-assigned UUID for this allocation block.
  TextColumn get allocationId => text()();

  TextColumn get companyId => text()();
  TextColumn get deviceId => text()();
  TextColumn get financialYearId => text()();

  /// e.g. 'SALES', 'PURCHASE', 'CREDIT_NOTE'
  TextColumn get series => text()();

  /// e.g. 'INVOICE', 'BILL', 'CREDIT_NOTE'
  TextColumn get documentType => text()();
  TextColumn get prefix => text().withDefault(const Constant(''))();
  TextColumn get suffix => text().nullable()();
  IntColumn get paddingDigits => integer().withDefault(const Constant(4))();

  /// Start of the allocated range (inclusive).
  IntColumn get fromNum => integer()();

  /// End of the allocated range (inclusive).
  IntColumn get toNum => integer()();

  /// How many numbers from this block have been consumed.
  IntColumn get used => integer().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get allocatedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  List<Set<Column>> get uniqueConstraints => [
    {companyId, deviceId, series, financialYearId, allocationId},
  ];
}

// ── Invoice header ────────────────────────────────────────────────────────────

/// One row per invoice, whether draft or issued.
///
/// The invoice [number] is NULL for drafts — it is assigned only at the
/// issue/post boundary when a number is consumed from a [NumberAllocations]
/// block.  After issuance the header is immutable; corrections create a
/// credit/debit note against the original.
class Invoices extends Table {
  TextColumn get localId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get companyId => text()();

  // ── Numbering (nullable for drafts) ──────────────────────────────────────────

  /// Assigned at issue time.  Null for draft invoices.
  IntColumn get number => integer().nullable()();
  TextColumn get displayNumber => text().nullable()();
  TextColumn get allocationId => text().nullable()(); // FK to NumberAllocations

  // ── Business fields ─────────────────────────────────────────────────────────

  TextColumn get invoiceDate => text()(); // ISO date
  TextColumn get dueDate => text().nullable()();
  TextColumn get customerId => text()(); // FK — remoteId of a Contact
  TextColumn get customerName => text()();
  TextColumn get customerGstin => text().nullable()();
  TextColumn get customerStateCode => text().nullable()();

  /// Currency, payment terms, reference.
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  TextColumn get paymentTerms => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();

  // ── Monetary totals (in paise) ──────────────────────────────────────────────

  IntColumn get totalBeforeTaxPaise => integer()();
  IntColumn get taxPaise => integer()();
  IntColumn get discountPaise => integer().withDefault(const Constant(0))();
  IntColumn get shippingPaise => integer().withDefault(const Constant(0))();
  IntColumn get totalPaise => integer()();

  // ── Lifecycle & sync ────────────────────────────────────────────────────────

  /// One of: 'draft', 'issued'.
  TextColumn get lifecycleStatus =>
      text().withDefault(const Constant('draft'))();

  /// [SyncStatus.name]
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();

  IntColumn get localRevision => integer().withDefault(const Constant(0))();
  IntColumn get remoteRevision => integer().nullable()();

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

// ── Invoice lines ─────────────────────────────────────────────────────────────

/// One row per line item on an invoice.
class InvoiceLines extends Table {
  TextColumn get localId => text()();
  TextColumn get invoiceLocalId => text()(); // FK to Invoices.localId

  TextColumn get productId => text().nullable()();
  TextColumn get productName => text()();
  TextColumn get description => text().nullable()();
  TextColumn get hsnSac => text().nullable()();

  /// Unit price in paise (or paise-equivalent for precision).
  IntColumn get unitPricePaise => integer()();

  /// Quantity — stored as TEXT for arbitrary precision (e.g. "10.500").
  TextColumn get quantity => text()();

  IntColumn get amountPaise => integer()();
  IntColumn get discountPaise => integer().withDefault(const Constant(0))();

  /// Net line total (amount - discount) before tax.
  IntColumn get netPaise => integer()();
  IntColumn get taxRateBasisPoints =>
      integer().withDefault(const Constant(0))();
  IntColumn get taxPaise => integer().withDefault(const Constant(0))();

  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}

// ── Invoice tax breakdown ─────────────────────────────────────────────────────

/// Per-tax-rate breakdown for an invoice line or the whole invoice.
class InvoiceTaxLines extends Table {
  TextColumn get localId => text()();
  TextColumn get invoiceLocalId => text()();

  /// FK to InvoiceLines.localId, or '*' for invoice-level taxes.
  TextColumn get lineLocalId => text()();

  /// 'IGST', 'CGST', 'SGST', 'CESS', 'NONE'
  TextColumn get taxType => text()();
  TextColumn get taxRate => text()(); // e.g. "18.0000"
  IntColumn get taxableAmountPaise => integer()();
  IntColumn get taxAmountPaise => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}
