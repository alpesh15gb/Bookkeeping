/// Purchase return form state — return goods against a posted vendor bill.
library;

import '../models/purchase_return_line.dart';

class PurchaseReturnFormState {
  const PurchaseReturnFormState({
    this.billId,
    this.billNumber = '',
    this.contactName = '',
    this.contactId = '',
    this.posStateCode = '',
    this.returnDate = '',
    this.notes,
    this.lines = const [],
    this.loadingBill = false,
    this.saving = false,
    this.error,
  });

  final String? billId;
  final String billNumber;
  final String contactName;
  final String contactId;
  final String posStateCode;
  final String returnDate;
  final String? notes;
  final List<PurchaseReturnLine> lines;
  final bool loadingBill;
  final bool saving;
  final String? error;

  bool get hasBill => (billId ?? '').isNotEmpty;

  /// Preview total (backend recomputes authoritative totals on create).
  double get previewTotal => lines.fold<double>(
    0,
    (s, l) => s + l.quantityReturned * l.rate * (1 + l.gstRate / 100),
  );
  double get previewSubtotal =>
      lines.fold<double>(0, (s, l) => s + l.quantityReturned * l.rate);
  double get totalReturnedQty =>
      lines.fold<double>(0, (s, l) => s + l.quantityReturned);

  PurchaseReturnFormState copyWith({
    String? billId,
    String? billNumber,
    String? contactName,
    String? contactId,
    String? posStateCode,
    String? returnDate,
    String? notes,
    List<PurchaseReturnLine>? lines,
    bool? loadingBill,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => PurchaseReturnFormState(
    billId: billId ?? this.billId,
    billNumber: billNumber ?? this.billNumber,
    contactName: contactName ?? this.contactName,
    contactId: contactId ?? this.contactId,
    posStateCode: posStateCode ?? this.posStateCode,
    returnDate: returnDate ?? this.returnDate,
    notes: notes ?? this.notes,
    lines: lines ?? this.lines,
    loadingBill: loadingBill ?? this.loadingBill,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
