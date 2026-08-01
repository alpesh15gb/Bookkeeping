library;

import 'package:flutter/foundation.dart';

@immutable
class PostCreditNoteCommand {
  const PostCreditNoteCommand({
    required this.companyId,
    required this.creditNoteDate,
    required this.customerId,
    required this.customerName,
    required this.deviceId,
    required this.financialYearId,
    required this.totalPaise,
    this.totalBeforeTaxPaise = 0,
    this.taxPaise = 0,
    this.sourceInvoiceLocalId,
    this.referenceNumber,
    this.description,
  });
  final String companyId;
  final String creditNoteDate;
  final String customerId;
  final String customerName;
  final String deviceId;
  final String financialYearId;
  final int totalPaise;
  final int totalBeforeTaxPaise;
  final int taxPaise;
  final String? sourceInvoiceLocalId;
  final String? referenceNumber;
  final String? description;
}

@immutable
class PostDebitNoteCommand {
  const PostDebitNoteCommand({
    required this.companyId,
    required this.debitNoteDate,
    required this.supplierId,
    required this.supplierName,
    required this.deviceId,
    required this.financialYearId,
    required this.totalPaise,
    this.totalBeforeTaxPaise = 0,
    this.taxPaise = 0,
    this.sourceInvoiceLocalId,
    this.referenceNumber,
    this.description,
  });
  final String companyId;
  final String debitNoteDate;
  final String supplierId;
  final String supplierName;
  final String deviceId;
  final String financialYearId;
  final int totalPaise;
  final int totalBeforeTaxPaise;
  final int taxPaise;
  final String? sourceInvoiceLocalId;
  final String? referenceNumber;
  final String? description;
}
