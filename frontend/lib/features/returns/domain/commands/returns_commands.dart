library;

import 'package:flutter/foundation.dart';

@immutable
class PostSalesReturnCommand {
  const PostSalesReturnCommand({
    required this.companyId,
    required this.returnDate,
    required this.customerId,
    required this.customerName,
    required this.totalPaise,
    this.sourceInvoiceLocalId,
    this.referenceNumber,
    this.description,
    required this.lines,
  });
  final String companyId;
  final String returnDate;
  final String customerId;
  final String customerName;
  final String? sourceInvoiceLocalId;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final List<SalesReturnLineCommand> lines;
}

@immutable
class SalesReturnLineCommand {
  const SalesReturnLineCommand({
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPricePaise,
    required this.totalPaise,
    this.sourceInvoiceLineLocalId,
  });
  final String? sourceInvoiceLineLocalId;
  final String productName;
  final String unit;
  final String quantity;
  final int unitPricePaise;
  final int totalPaise;
}

@immutable
class PostPurchaseReturnCommand {
  const PostPurchaseReturnCommand({
    required this.companyId,
    required this.returnDate,
    required this.supplierId,
    required this.supplierName,
    required this.totalPaise,
    this.sourceReceiptLocalId,
    this.referenceNumber,
    this.description,
    required this.lines,
  });
  final String companyId;
  final String returnDate;
  final String supplierId;
  final String supplierName;
  final String? sourceReceiptLocalId;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final List<PurchaseReturnLineCommand> lines;
}

@immutable
class PurchaseReturnLineCommand {
  const PurchaseReturnLineCommand({
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitCostPaise,
    required this.totalPaise,
    this.sourceReceiptLineLocalId,
  });
  final String? sourceReceiptLineLocalId;
  final String productName;
  final String unit;
  final String quantity;
  final int unitCostPaise;
  final int totalPaise;
}
