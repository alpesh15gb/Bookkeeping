/// Commands for invoice operations.
library;

import 'package:flutter/foundation.dart';

@immutable
class SaveInvoiceDraftCommand {
  const SaveInvoiceDraftCommand({
    required this.companyId,
    required this.invoiceDate,
    required this.customerId,
    required this.customerName,
    this.customerGstin,
    this.customerStateCode,
    this.dueDate,
    this.referenceNumber,
    this.paymentTerms,
    this.totalBeforeTaxPaise = 0,
    this.taxPaise = 0,
    this.discountPaise = 0,
    this.shippingPaise = 0,
    this.totalPaise = 0,
    this.lines = const [],
  });

  final String companyId;
  final String invoiceDate;
  final String customerId;
  final String customerName;
  final String? customerGstin;
  final String? customerStateCode;
  final String? dueDate;
  final String? referenceNumber;
  final String? paymentTerms;
  final int totalBeforeTaxPaise;
  final int taxPaise;
  final int discountPaise;
  final int shippingPaise;
  final int totalPaise;
  final List<InvoiceLineCommand> lines;
}

@immutable
class InvoiceLineCommand {
  const InvoiceLineCommand({
    this.productId,
    required this.productName,
    this.description,
    this.hsnSac,
    required this.unitPricePaise,
    required this.quantity,
    required this.amountPaise,
    this.discountPaise = 0,
    this.taxRateBasisPoints = 0,
    this.taxPaise = 0,
    required this.netPaise,
    required this.sortOrder,
  });

  final String? productId;
  final String productName;
  final String? description;
  final String? hsnSac;
  final int unitPricePaise;
  final String quantity;
  final int amountPaise;
  final int discountPaise;
  final int taxRateBasisPoints;
  final int taxPaise;
  final int netPaise;
  final int sortOrder;
}

/// Issuing consumes a number and freezes the invoice.
@immutable
class IssueInvoiceCommand {
  const IssueInvoiceCommand({
    required this.localId,
    required this.companyId,
    required this.deviceId,
    required this.financialYearId,
    this.series = 'SALES',
  });

  final String localId;
  final String companyId;
  final String deviceId;
  final String financialYearId;
  final String series;
}
