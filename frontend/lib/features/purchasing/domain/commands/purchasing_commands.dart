/// Commands for the purchasing workflow.
library;

import 'package:flutter/foundation.dart';

@immutable
class SavePurchaseOrderDraftCommand {
  const SavePurchaseOrderDraftCommand({
    required this.companyId,
    required this.orderDate,
    required this.supplierId,
    required this.supplierName,
    this.referenceNumber,
    this.description,
    this.totalPaise = 0,
    this.lines = const [],
  });
  final String companyId;
  final String orderDate;
  final String supplierId;
  final String supplierName;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final List<PurchaseOrderLineCommand> lines;
}

@immutable
class PurchaseOrderLineCommand {
  const PurchaseOrderLineCommand({
    required this.productName,
    required this.unit,
    required this.unitPricePaise,
    required this.quantityOrdered,
    required this.totalPaise,
    required this.sortOrder,
    this.description,
  });
  final String productName;
  final String? description;
  final String unit;
  final int unitPricePaise;
  final String quantityOrdered;
  final int totalPaise;
  final int sortOrder;
}

@immutable
class ReceiveGoodsCommand {
  const ReceiveGoodsCommand({
    required this.companyId,
    required this.purchaseOrderLocalId,
    required this.receiptDate,
    required this.supplierId,
    required this.supplierName,
    this.referenceNumber,
    this.description,
    required this.lines,
  });
  final String companyId;
  final String purchaseOrderLocalId;
  final String receiptDate;
  final String supplierId;
  final String supplierName;
  final String? referenceNumber;
  final String? description;
  final List<ReceiveLineCommand> lines;
}

@immutable
class ReceiveLineCommand {
  const ReceiveLineCommand({
    required this.purchaseOrderLineLocalId,
    required this.productName,
    required this.unit,
    required this.quantityReceived,
    required this.unitCostPaise,
    required this.sortOrder,
  });
  final String purchaseOrderLineLocalId;
  final String productName;
  final String unit;
  final String quantityReceived;
  final int unitCostPaise;
  final int sortOrder;
}

@immutable
class PostSupplierInvoiceCommand {
  const PostSupplierInvoiceCommand({
    required this.companyId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.supplierId,
    required this.supplierName,
    this.referenceNumber,
    this.description,
    this.totalBeforeTaxPaise = 0,
    this.taxPaise = 0,
    this.totalPaise = 0,
    this.lines = const [],
  });
  final String companyId;
  final String invoiceNumber;
  final String invoiceDate;
  final String supplierId;
  final String supplierName;
  final String? referenceNumber;
  final String? description;
  final int totalBeforeTaxPaise;
  final int taxPaise;
  final int totalPaise;
  final List<SupplierInvoiceLineCommand> lines;
}

@immutable
class SupplierInvoiceLineCommand {
  const SupplierInvoiceLineCommand({
    required this.productName,
    required this.unit,
    required this.unitPricePaise,
    required this.quantity,
    required this.totalPaise,
    required this.sortOrder,
    this.description,
  });
  final String productName;
  final String? description;
  final String unit;
  final int unitPricePaise;
  final String quantity;
  final int totalPaise;
  final int sortOrder;
}
