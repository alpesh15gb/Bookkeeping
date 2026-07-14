/// Numbering series model for invoice/document series.
library;

import 'package:flutter/foundation.dart';

/// A numbering series configuration for a document type (invoice, bill, etc.).
@immutable
class InvoiceSeries {
  const InvoiceSeries({
    required this.id,
    required this.documentType,
    this.prefix = '',
    this.suffix = '',
    this.nextNumber = 1,
    this.paddingDigits = 3,
    this.isActive = true,
    this.description,
    this.createdAt,
  });

  factory InvoiceSeries.fromJson(Map<String, dynamic> json) {
    return InvoiceSeries(
      id: json['id'] as String,
      documentType: json['document_type'] as String,
      prefix: (json['prefix'] as String?) ?? '',
      suffix: (json['suffix'] as String?) ?? '',
      nextNumber: (json['next_number'] as num?)?.toInt() ?? 1,
      paddingDigits: (json['padding_digits'] as num?)?.toInt() ?? 3,
      isActive: (json['is_active'] as bool?) ?? true,
      description: json['description'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  final String id;
  final String documentType;
  final String prefix;
  final String suffix;
  final int nextNumber;
  final int paddingDigits;
  final bool isActive;
  final String? description;
  final DateTime? createdAt;

  /// Formatted preview like "INV-001".
  String get preview {
    final padded = nextNumber.toString().padLeft(paddingDigits, '0');
    return '$prefix$padded$suffix';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'document_type': documentType,
    'prefix': prefix,
    'suffix': suffix,
    'next_number': nextNumber,
    'padding_digits': paddingDigits,
    'is_active': isActive,
    'description': description,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceSeries &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Known document types for series configuration.
class DocumentType {
  DocumentType._();
  static const String invoice = 'INVOICE';
  static const String proforma = 'PROFORMA_INVOICE';
  static const String salesOrder = 'SALES_ORDER';
  static const String deliveryChallan = 'DELIVERY_CHALLAN';
  static const String purchaseOrder = 'PURCHASE_ORDER';
  static const String bill = 'BILL';
  static const String vendorPayment = 'DISBURSEMENT';
  static const String salesReturn = 'SALES_RETURN';
  static const String purchaseReturn = 'PURCHASE_RETURN';
  static const String creditNote = 'CREDIT_NOTE';
  static const String debitNote = 'DEBIT_NOTE';
  static const String receipt = 'RECEIPT';
  static const String payment = 'PAYMENT';
  static const String journal = 'JOURNAL';

  /// All known document types with their display labels.
  static Map<String, String> get labels => {
    invoice: 'Invoice',
    proforma: 'Proforma / Quotation',
    salesOrder: 'Sales Order',
    deliveryChallan: 'Delivery Challan',
    purchaseOrder: 'Purchase Order',
    bill: 'Bill',
    vendorPayment: 'Vendor Payment',
    salesReturn: 'Sales Return',
    purchaseReturn: 'Purchase Return',
    creditNote: 'Credit Note',
    debitNote: 'Debit Note',
    receipt: 'Receipt',
    payment: 'Payment',
    journal: 'Journal',
  };
}
