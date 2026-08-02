/// Invoice Form State — Complete state for the invoice form.
library;

import 'package:flutter/foundation.dart';
import '../models/invoice_line.dart';
import '../models/invoice_status.dart';

@immutable
class InvoiceFormState {
  const InvoiceFormState({
    this.contactId,
    this.contactName = '',
    this.invoiceNumber = '',
    this.issueDate,
    this.dueDate,
    this.posStateCode = '',
    this.shippingCharges = 0,
    this.notes,
    this.termsAndConditions,
    this.referenceNumber,
    this.isGstInclusive = false,
    this.isRcm = false,
    this.supplyType = 'DOMESTIC',
    this.tdsRate,
    this.tcsRate,
    this.lines = const [],
    this.editingLineIndex,
    this.originalId,
    this.originalStatus,
    this.calculatedSubtotal = 0,
    this.calculatedDiscountTotal = 0,
    this.calculatedTaxableValue = 0,
    this.calculatedCgstAmount = 0,
    this.calculatedSgstAmount = 0,
    this.calculatedIgstAmount = 0,
    this.calculatedUtgstAmount = 0,
    this.calculatedCessAmount = 0,
    this.calculatedShippingCharges = 0,
    this.calculatedRoundOff = 0,
    this.calculatedTotal = 0,
    this.calculatedTaxBreakdown = const [],
    this.lineCalculations = const [],
    this.billingAddress,
    this.shippingAddress,
    this.contactGstNumber,
    this.contactEmail,
    this.contactPhone,
    this.validationErrors = const {},
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  // Header fields
  final String? contactId;
  final String contactName;
  final String invoiceNumber;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String posStateCode;
  final double shippingCharges;
  final String? notes;
  final String? termsAndConditions;
  final String? referenceNumber;
  final bool isGstInclusive;
  final bool isRcm;
  final String supplyType;
  final double? tdsRate;
  final double? tcsRate;

  // Lines
  final List<InvoiceLine> lines;
  final int? editingLineIndex;

  // Original invoice (for edit mode)
  final String? originalId;
  final InvoiceStatus? originalStatus;

  // Calculated totals
  final double calculatedSubtotal;
  final double calculatedDiscountTotal;
  final double calculatedTaxableValue;
  final double calculatedCgstAmount;
  final double calculatedSgstAmount;
  final double calculatedIgstAmount;
  final double calculatedUtgstAmount;
  final double calculatedCessAmount;
  final double calculatedShippingCharges;
  final double calculatedRoundOff;
  final double calculatedTotal;
  final List<TaxBreakdownItem> calculatedTaxBreakdown;
  final List<LineCalculation> lineCalculations;

  // Contact details (for display)
  final String? billingAddress;
  final String? shippingAddress;
  final String? contactGstNumber;
  final String? contactEmail;
  final String? contactPhone;

  // Validation
  final Map<String, String> validationErrors;

  // Loading states
  final bool isLoading;
  final bool isSaving;
  final String? error;

  // Convenience getters
  bool get isEditMode => originalId != null;
  bool get isValid => validationErrors.isEmpty;
  bool get hasLines => lines.isNotEmpty;
  int get lineCount => lines.length;
  double get totalTax => calculatedCgstAmount + calculatedSgstAmount + calculatedIgstAmount + calculatedUtgstAmount + calculatedCessAmount;

  InvoiceFormState copyWith({
    String? contactId,
    String? contactName,
    String? invoiceNumber,
    DateTime? issueDate,
    DateTime? dueDate,
    String? posStateCode,
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
    int? editingLineIndex,
    String? originalId,
    InvoiceStatus? originalStatus,
    double? calculatedSubtotal,
    double? calculatedDiscountTotal,
    double? calculatedTaxableValue,
    double? calculatedCgstAmount,
    double? calculatedSgstAmount,
    double? calculatedIgstAmount,
    double? calculatedUtgstAmount,
    double? calculatedCessAmount,
    double? calculatedShippingCharges,
    double? calculatedRoundOff,
    double? calculatedTotal,
    List<TaxBreakdownItem>? calculatedTaxBreakdown,
    List<LineCalculation>? lineCalculations,
    String? billingAddress,
    String? shippingAddress,
    String? contactGstNumber,
    String? contactEmail,
    String? contactPhone,
    Map<String, String>? validationErrors,
    bool? isLoading,
    bool? isSaving,
    String? error,
  }) {
    return InvoiceFormState(
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      posStateCode: posStateCode ?? this.posStateCode,
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
      editingLineIndex: editingLineIndex ?? this.editingLineIndex,
      originalId: originalId ?? this.originalId,
      originalStatus: originalStatus ?? this.originalStatus,
      calculatedSubtotal: calculatedSubtotal ?? this.calculatedSubtotal,
      calculatedDiscountTotal: calculatedDiscountTotal ?? this.calculatedDiscountTotal,
      calculatedTaxableValue: calculatedTaxableValue ?? this.calculatedTaxableValue,
      calculatedCgstAmount: calculatedCgstAmount ?? this.calculatedCgstAmount,
      calculatedSgstAmount: calculatedSgstAmount ?? this.calculatedSgstAmount,
      calculatedIgstAmount: calculatedIgstAmount ?? this.calculatedIgstAmount,
      calculatedUtgstAmount: calculatedUtgstAmount ?? this.calculatedUtgstAmount,
      calculatedCessAmount: calculatedCessAmount ?? this.calculatedCessAmount,
      calculatedShippingCharges: calculatedShippingCharges ?? this.calculatedShippingCharges,
      calculatedRoundOff: calculatedRoundOff ?? this.calculatedRoundOff,
      calculatedTotal: calculatedTotal ?? this.calculatedTotal,
      calculatedTaxBreakdown: calculatedTaxBreakdown ?? this.calculatedTaxBreakdown,
      lineCalculations: lineCalculations ?? this.lineCalculations,
      billingAddress: billingAddress ?? this.billingAddress,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      contactGstNumber: contactGstNumber ?? this.contactGstNumber,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      validationErrors: validationErrors ?? this.validationErrors,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error ?? this.error,
    );
  }
}

/// Tax breakdown item for GST compliance display.
@immutable
class TaxBreakdownItem {
  const TaxBreakdownItem({
    required this.label,
    required this.rate,
    required this.taxableValue,
    required this.amount,
  });

  final String label; // CGST, SGST, IGST, UTGST, Cess
  final double rate; // Percentage
  final double taxableValue;
  final double amount;
}

/// Line-level calculation for display in table.
@immutable
class LineCalculation {
  const LineCalculation({
    required this.lineIndex,
    required this.subtotal,
    required this.discountAmount,
    required this.taxableValue,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.utgstAmount,
    required this.cessAmount,
    required this.total,
  });

  final int lineIndex;
  final double subtotal;
  final double discountAmount;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double total;

  double get totalTax => cgstAmount + sgstAmount + igstAmount + utgstAmount + cessAmount;
}