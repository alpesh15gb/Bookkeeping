/// Goods receipt form state — receive goods against a confirmed purchase order.
library;

import '../models/goods_receipt_line.dart';

class GoodsReceiptFormState {
  const GoodsReceiptFormState({
    this.purchaseOrderId = '',
    this.poNumber = '',
    this.contactName = '',
    this.receiptDate = '',
    this.notes,
    this.lines = const [],
    this.loadingPo = false,
    this.saving = false,
    this.error,
  });

  final String purchaseOrderId;
  final String poNumber;
  final String contactName;
  final String receiptDate;
  final String? notes;
  final List<GoodsReceiptLine> lines;
  final bool loadingPo;
  final bool saving;
  final String? error;

  bool get hasPo => purchaseOrderId.isNotEmpty;

  GoodsReceiptFormState copyWith({
    String? purchaseOrderId,
    String? poNumber,
    String? contactName,
    String? receiptDate,
    String? notes,
    List<GoodsReceiptLine>? lines,
    bool? loadingPo,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => GoodsReceiptFormState(
    purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
    poNumber: poNumber ?? this.poNumber,
    contactName: contactName ?? this.contactName,
    receiptDate: receiptDate ?? this.receiptDate,
    notes: notes ?? this.notes,
    lines: lines ?? this.lines,
    loadingPo: loadingPo ?? this.loadingPo,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
