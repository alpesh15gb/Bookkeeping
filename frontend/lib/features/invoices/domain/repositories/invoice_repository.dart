/// Repository interface for invoices and number allocations.
library;

import '../entities/invoice_entity.dart';
import '../commands/invoice_commands.dart';

abstract interface class InvoiceRepository {
  // ── Number allocations ────────────────────────────────────────────────────

  /// Returns the active number allocation for the given scoping key.
  /// Null if no range has been allocated yet (first issue requires a pull).
  Future<NumberAllocationEntity?> currentAllocation({
    required String companyId,
    required String deviceId,
    required String financialYearId,
    required String series,
    required String documentType,
  });

  /// Return a usable local range, requesting and persisting a new lease when
  /// connected and the previous range is missing or exhausted.
  Future<NumberAllocationEntity?> ensureAllocation({
    String companyId = '',
    String deviceId = '',
    String financialYearId = '',
    String series = 'SALES',
    String documentType = 'INVOICE',
  });

  // ── Invoice read ─────────────────────────────────────────────────────────

  /// Watch invoices for the current company (Drift stream).
  Stream<List<InvoiceEntity>> watchInvoices({String? companyId});

  /// Get a single invoice by localId.
  Future<InvoiceEntity?> getInvoice(String localId);

  // ── Draft ────────────────────────────────────────────────────────────────

  /// Save or update a draft invoice.  Does NOT consume a number.
  Future<InvoiceEntity> saveDraft(SaveInvoiceDraftCommand command);

  // ── Issue (consumes number) ──────────────────────────────────────────────

  /// Issue the invoice: consume the next number, freeze the record,
  /// create the journal entry, and queue the sync operation.
  ///
  /// Throws [ValidationException] if:
  /// - The invoice is not in draft state.
  /// - The totals are unbalanced.
  /// - No number allocation is available (range exhausted or not pulled).
  Future<InvoiceEntity> issue(IssueInvoiceCommand command);

  // ── Sync ─────────────────────────────────────────────────────────────────

  /// Re-queue a failed sync operation.
  Future<void> retrySync(String localId);
}
