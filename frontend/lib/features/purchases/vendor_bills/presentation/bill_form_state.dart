/// Bill form state — create-only (backend exposes no bill update endpoint for draft).
library;

import '../models/bill_line.dart';

class BillFormState {
  const BillFormState({
    this.billNumber = '',
    this.contactId,
    this.contactName = '',
    this.issueDate = '',
    this.dueDate = '',
    this.referenceNumber,
    this.posStateCode = '',
    this.tdsRate = 0,
    this.itcEligible = true,
    this.isGstInclusive = false,
    this.notes,
    this.termsAndConditions,
    this.lines = const [],
    this.subtotal = 0,
    this.discountTotal = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.totalTax = 0,
    this.total = 0,
    this.tdsAmount = 0,
    this.saving = false,
    this.error,
  });

  final String billNumber;
  final String? contactId;
  final String contactName;
  final String issueDate;
  final String dueDate;
  final String? referenceNumber;
  final String posStateCode;
  final double tdsRate;
  final bool itcEligible;
  final bool isGstInclusive;
  final String? notes;
  final String? termsAndConditions;
  final List<BillLine> lines;
  final double subtotal;
  final double discountTotal;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double totalTax;
  final double total;
  final double tdsAmount;
  final bool saving;
  final String? error;

  BillFormState copyWith({
    String? billNumber,
    String? contactId,
    String? contactName,
    String? issueDate,
    String? dueDate,
    String? referenceNumber,
    String? posStateCode,
    double? tdsRate,
    bool? itcEligible,
    bool? isGstInclusive,
    String? notes,
    String? termsAndConditions,
    List<BillLine>? lines,
    double? subtotal,
    double? discountTotal,
    double? cgstAmount,
    double? sgstAmount,
    double? igstAmount,
    double? totalTax,
    double? total,
    double? tdsAmount,
    bool? saving,
    String? error,
    bool clearReferenceNumber = false,
    bool clearNotes = false,
    bool clearTermsAndConditions = false,
    bool clearError = false,
  }) => BillFormState(
    billNumber: billNumber ?? this.billNumber,
    contactId: contactId ?? this.contactId,
    contactName: contactName ?? this.contactName,
    issueDate: issueDate ?? this.issueDate,
    dueDate: dueDate ?? this.dueDate,
    referenceNumber: clearReferenceNumber
        ? null
        : (referenceNumber ?? this.referenceNumber),
    posStateCode: posStateCode ?? this.posStateCode,
    tdsRate: tdsRate ?? this.tdsRate,
    itcEligible: itcEligible ?? this.itcEligible,
    isGstInclusive: isGstInclusive ?? this.isGstInclusive,
    notes: clearNotes ? null : (notes ?? this.notes),
    termsAndConditions: clearTermsAndConditions
        ? null
        : (termsAndConditions ?? this.termsAndConditions),
    lines: lines ?? this.lines,
    subtotal: subtotal ?? this.subtotal,
    discountTotal: discountTotal ?? this.discountTotal,
    cgstAmount: cgstAmount ?? this.cgstAmount,
    sgstAmount: sgstAmount ?? this.sgstAmount,
    igstAmount: igstAmount ?? this.igstAmount,
    totalTax: totalTax ?? this.totalTax,
    total: total ?? this.total,
    tdsAmount: tdsAmount ?? this.tdsAmount,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
  );
}
