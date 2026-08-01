/// Invoice form state management — Riverpod StateNotifier.
///
/// The form captures user intent. The repository remains authoritative for
/// totals, numbering, lifecycle transitions, and outbox writes.
/// UI-derived totals are previews only — the repository recomputes on save.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/utils/money.dart';
import '../../domain/commands/invoice_commands.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../providers/invoice_providers.dart';

/// A single editable line on the invoice form.
class InvoiceFormLine {
  const InvoiceFormLine({
    this.productId,
    this.productName = '',
    this.description,
    this.hsnSac,
    this.unitPricePaise = 0,
    this.quantity = '1',
    this.discountPaise = 0,
    this.taxRateBasisPoints = 0,
  });

  final String? productId;
  final String productName;
  final String? description;
  final String? hsnSac;
  final int unitPricePaise;
  final String quantity;
  final int discountPaise;
  final int taxRateBasisPoints;

  int get amountPaise {
    final qty = double.tryParse(quantity) ?? 0;
    return (unitPricePaise * qty).round();
  }

  int get netPaise => amountPaise - discountPaise;
  int get taxPaise => (netPaise * taxRateBasisPoints / 10000).round();

  InvoiceFormLine copyWith({
    String? productId,
    String? productName,
    String? description,
    String? hsnSac,
    int? unitPricePaise,
    String? quantity,
    int? discountPaise,
    int? taxRateBasisPoints,
  }) => InvoiceFormLine(
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    description: description ?? this.description,
    hsnSac: hsnSac ?? this.hsnSac,
    unitPricePaise: unitPricePaise ?? this.unitPricePaise,
    quantity: quantity ?? this.quantity,
    discountPaise: discountPaise ?? this.discountPaise,
    taxRateBasisPoints: taxRateBasisPoints ?? this.taxRateBasisPoints,
  );
}

/// Immutable form state — represents user intent only.
class InvoiceFormState {
  const InvoiceFormState({
    this.localId,
    this.remoteId,
    this.invoiceDate = '',
    this.customerId = '',
    this.customerName = '',
    this.customerGstin,
    this.customerStateCode,
    this.dueDate,
    this.referenceNumber,
    this.paymentTerms,
    this.lines = const [],
    this.totalBeforeTaxPaise = 0,
    this.taxPaise = 0,
    this.discountPaise = 0,
    this.shippingPaise = 0,
    this.totalPaise = 0,
    this.saving = false,
    this.error,
    this.lastSaved,
    this.lifecycleStatus = 'draft',
    this.syncStatus,
  });

  final String? localId;
  final String? remoteId;
  final String invoiceDate;
  final String customerId;
  final String customerName;
  final String? customerGstin;
  final String? customerStateCode;
  final String? dueDate;
  final String? referenceNumber;
  final String? paymentTerms;
  final List<InvoiceFormLine> lines;
  final int totalBeforeTaxPaise;
  final int taxPaise;
  final int discountPaise;
  final int shippingPaise;
  final int totalPaise;
  final bool saving;
  final String? error;
  final DateTime? lastSaved;
  final String lifecycleStatus;
  final String? syncStatus;

  bool get isDraft => lifecycleStatus == 'draft';
  bool get isIssued => lifecycleStatus == 'issued';
  bool get hasLines => lines.isNotEmpty;
  bool get hasCustomer => customerId.isNotEmpty;
  bool get isValid =>
      invoiceDate.isNotEmpty &&
      hasCustomer &&
      hasLines &&
      lines.every(
        (l) =>
            l.productId != null &&
            l.productName.isNotEmpty &&
            l.amountPaise > 0 &&
            l.discountPaise >= 0 &&
            l.discountPaise <= l.amountPaise,
      ) &&
      totalPaise > 0;

  Money get totalPreview => Money.fromPaise(totalPaise);
  Money get taxPreview => Money.fromPaise(taxPaise);
  Money get subtotalPreview =>
      Money.fromPaise(lines.fold(0, (s, l) => s + l.amountPaise));

  InvoiceFormState copyWith({
    String? localId,
    String? remoteId,
    String? invoiceDate,
    String? customerId,
    String? customerName,
    String? customerGstin,
    String? customerStateCode,
    String? dueDate,
    String? referenceNumber,
    String? paymentTerms,
    List<InvoiceFormLine>? lines,
    int? totalBeforeTaxPaise,
    int? taxPaise,
    int? discountPaise,
    int? shippingPaise,
    int? totalPaise,
    bool? saving,
    String? error,
    DateTime? lastSaved,
    String? lifecycleStatus,
    String? syncStatus,
    bool clearError = false,
    bool clearLastSaved = false,
  }) => InvoiceFormState(
    localId: localId ?? this.localId,
    remoteId: remoteId ?? this.remoteId,
    invoiceDate: invoiceDate ?? this.invoiceDate,
    customerId: customerId ?? this.customerId,
    customerName: customerName ?? this.customerName,
    customerGstin: customerGstin ?? this.customerGstin,
    customerStateCode: customerStateCode ?? this.customerStateCode,
    dueDate: dueDate ?? this.dueDate,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    paymentTerms: paymentTerms ?? this.paymentTerms,
    lines: lines ?? this.lines,
    totalBeforeTaxPaise: totalBeforeTaxPaise ?? this.totalBeforeTaxPaise,
    taxPaise: taxPaise ?? this.taxPaise,
    discountPaise: discountPaise ?? this.discountPaise,
    shippingPaise: shippingPaise ?? this.shippingPaise,
    totalPaise: totalPaise ?? this.totalPaise,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
    lastSaved: clearLastSaved ? null : (lastSaved ?? this.lastSaved),
    lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
    syncStatus: syncStatus ?? this.syncStatus,
  );
}

/// Notifier for the invoice draft editor.
class InvoiceFormNotifier extends StateNotifier<InvoiceFormState> {
  InvoiceFormNotifier(this._repository) : super(const InvoiceFormState()) {
    final now = DateTime.now();
    state = state.copyWith(
      invoiceDate:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
  }

  final InvoiceRepository _repository;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(InvoiceFormState newState) {
    if (!_disposed) state = newState;
  }

  // ── Field setters ────────────────────────────────────────────────────────

  void setDate(String d) => _set(state.copyWith(invoiceDate: d));

  void setCustomer(String id, String name, {String? gstin, String? stateCode}) {
    _set(
      state.copyWith(
        customerId: id,
        customerName: name,
        customerGstin: gstin,
        customerStateCode: stateCode,
        clearError: true,
      ),
    );
  }

  void setDueDate(String d) => _set(state.copyWith(dueDate: d));
  void setReference(String r) => _set(state.copyWith(referenceNumber: r));
  void setPaymentTerms(String t) => _set(state.copyWith(paymentTerms: t));

  // ── Line management ──────────────────────────────────────────────────────

  void addLine() {
    _set(state.copyWith(lines: [...state.lines, const InvoiceFormLine()]));
  }

  void updateLine(int index, InvoiceFormLine line) {
    final lines = [...state.lines]..[index] = line;
    _recomputeTotals(lines);
  }

  void removeLine(int index) {
    if (state.lines.length <= 1) return;
    final lines = [...state.lines]..removeAt(index);
    _recomputeTotals(lines);
  }

  void _recomputeTotals(List<InvoiceFormLine> lines) {
    final subtotal = lines.fold<int>(0, (s, l) => s + l.amountPaise);
    final discount = lines.fold<int>(0, (s, l) => s + l.discountPaise);
    final netBeforeTax = subtotal - discount;
    final tax = lines.fold<int>(0, (sum, line) => sum + line.taxPaise);
    // Rounding: apply to the final total.
    final total = netBeforeTax + tax;
    _set(
      state.copyWith(
        lines: lines,
        totalBeforeTaxPaise: netBeforeTax,
        taxPaise: tax,
        discountPaise: discount,
        totalPaise: total,
        clearError: true,
      ),
    );
  }

  // ── Save draft ───────────────────────────────────────────────────────────

  Future<bool> saveDraft() async {
    if (state.saving || !state.isValid) return false;
    _set(state.copyWith(saving: true, clearError: true));

    try {
      final entity = await _repository.saveDraft(
        SaveInvoiceDraftCommand(
          companyId: '', // resolved by repository
          invoiceDate: state.invoiceDate,
          customerId: state.customerId,
          customerName: state.customerName,
          customerGstin: state.customerGstin,
          customerStateCode: state.customerStateCode,
          dueDate: state.dueDate,
          referenceNumber: state.referenceNumber,
          paymentTerms: state.paymentTerms,
          totalBeforeTaxPaise: state.totalBeforeTaxPaise,
          taxPaise: state.taxPaise,
          discountPaise: state.discountPaise,
          shippingPaise: state.shippingPaise,
          totalPaise: state.totalPaise,
          lines: state.lines
              .asMap()
              .entries
              .map(
                (e) => InvoiceLineCommand(
                  productId: e.value.productId,
                  productName: e.value.productName,
                  description: e.value.description,
                  hsnSac: e.value.hsnSac,
                  unitPricePaise: e.value.unitPricePaise,
                  quantity: e.value.quantity,
                  amountPaise: e.value.amountPaise,
                  discountPaise: e.value.discountPaise,
                  taxRateBasisPoints: e.value.taxRateBasisPoints,
                  taxPaise: e.value.taxPaise,
                  netPaise: e.value.netPaise,
                  sortOrder: e.key,
                ),
              )
              .toList(),
        ),
      );

      if (_disposed) return false;
      _set(
        state.copyWith(
          localId: entity.localId,
          remoteId: entity.remoteId,
          lifecycleStatus: entity.lifecycleStatus,
          syncStatus: entity.syncStatus.name,
          saving: false,
          lastSaved: DateTime.now(),
          // Overwrite with repository-derived totals.
          totalBeforeTaxPaise: entity.totalBeforeTaxPaise,
          taxPaise: entity.taxPaise,
          discountPaise: entity.discountPaise,
          shippingPaise: entity.shippingPaise,
          totalPaise: entity.totalPaise,
        ),
      );
      return true;
    } catch (e) {
      if (_disposed) return false;
      _set(state.copyWith(saving: false, error: e.toString()));
      return false;
    }
  }
}

/// Provider for the invoice form notifier.
final invoiceFormProvider =
    StateNotifierProvider.autoDispose<InvoiceFormNotifier, InvoiceFormState>((
      ref,
    ) {
      final repo = ref.watch(invoiceRepositoryProvider);
      return InvoiceFormNotifier(repo);
    });
