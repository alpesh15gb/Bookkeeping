/// Invoice form state model.
library;

import '../models/invoice_line.dart';

class InvoiceFormState {
  const InvoiceFormState({
    this.contactId,
    this.contactName = '',
    this.invoiceNumber = '',
    this.issueDate = '',
    this.dueDate = '',
    this.posStateCode = '',
    this.discountRate = 0,
    this.shippingCharges = 0,
    this.notes,
    this.termsAndConditions,
    this.referenceNumber,
    this.isGstInclusive = false,
    this.isRcm = false,
    this.supplyType = 'DOMESTIC',
    this.tdsRate = 0,
    this.tcsRate = 0,
    this.lines = const [],
    this.subtotal = 0,
    this.discountTotal = 0,
    this.totalTax = 0,
    this.total = 0,
    this.saving = false,
    this.error,
  });

  final String? contactId;
  final String contactName;
  final String invoiceNumber;
  final String issueDate;
  final String dueDate;
  final String posStateCode;
  final double discountRate;
  final double shippingCharges;
  final String? notes;
  final String? termsAndConditions;
  final String? referenceNumber;
  final bool isGstInclusive;
  final bool isRcm;
  final String supplyType;
  final double tdsRate;
  final double tcsRate;
  final List<InvoiceLine> lines;
  final double subtotal;
  final double discountTotal;
  final double totalTax;
  final double total;
  final bool saving;
  final String? error;

  bool get isValid =>
      contactId != null && contactId!.isNotEmpty && lines.any((l) => l.productId.isNotEmpty);

  InvoiceFormState copyWith({
    String? contactId,
    String? contactName,
    String? invoiceNumber,
    String? issueDate,
    String? dueDate,
    String? posStateCode,
    double? discountRate,
    double? shippingCharges,
    String? notes,
    String? termsAndConditions,
    String? referenceNumber,
    bool? isGstInclusive,
    bool? isRcm,
    String? supplyType,
    double? tdsRate,
    double? tcsRate,
    List<InvoiceLine>? lines,
    double? subtotal,
    double? discountTotal,
    double? totalTax,
    double? total,
    bool? saving,
    String? error,
    bool clearError = false,
  }) => InvoiceFormState(
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    issueDate: issueDate ?? this.issueDate,
    dueDate: dueDate ?? this.dueDate,
    posStateCode: posStateCode ?? this.posStateCode,
    discountRate: discountRate ?? this.discountRate,
    shippingCharges: shippingCharges ?? this.shippingCharges,
    notes: notes ?? this.notes,
    termsAndConditions: termsAndConditions ?? this.termsAndConditions,
    referenceNumber: referenceNumber ?? this.referenceNumber,
    isGstInclusive: isGstInclusive ?? this.isGstInclusive,
    isRcm: isRcm ?? this.isRcm,
    supplyType: supplyType ?? this.supplyType,
    tdsRate: tdsRate ?? this.tdsRate,
    tcsRate: tcsRate ?? this.tcsRate,
    lines: lines ?? this.lines,
    subtotal: subtotal ?? this.subtotal,
    discountTotal: discountTotal ?? this.discountTotal,
    totalTax: totalTax ?? this.totalTax,
    total: total ?? this.total,
    saving: saving ?? this.saving,
    error: error ?? (clearError ? null : this.error),
  );
}
