/// Purchase order form state — create-only (backend exposes no PO update).
library;

import '../models/purchase_order_line.dart';

class PurchaseOrderFormState {
  const PurchaseOrderFormState({
    this.poNumber = '',
    this.contactId,
    this.contactName = '',
    this.orderDate = '',
    this.dueDate = '',
    this.posStateCode = '',
    this.lines = const [],
    this.subtotal = 0,
    this.discountTotal = 0,
    this.totalTax = 0,
    this.total = 0,
    this.saving = false,
    this.error,
  });

  final String poNumber;
  final String? contactId;
  final String contactName;
  final String orderDate;
  final String dueDate;
  final String posStateCode;
  final List<PurchaseOrderLine> lines;
  final double subtotal;
  final double discountTotal;
  final double totalTax;
  final double total;
  final bool saving;
  final String? error;

  PurchaseOrderFormState copyWith({
    String? poNumber,
    String? contactId,
    String? contactName,
    String? orderDate,
    String? dueDate,
    String? posStateCode,
    List<PurchaseOrderLine>? lines,
    double? subtotal,
    double? discountTotal,
    double? totalTax,
    double? total,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => PurchaseOrderFormState(
    poNumber: poNumber ?? this.poNumber,
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    orderDate: orderDate ?? this.orderDate,
    dueDate: dueDate ?? this.dueDate,
    posStateCode: posStateCode ?? this.posStateCode,
    lines: lines ?? this.lines,
    subtotal: subtotal ?? this.subtotal,
    discountTotal: discountTotal ?? this.discountTotal,
    totalTax: totalTax ?? this.totalTax,
    total: total ?? this.total,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
