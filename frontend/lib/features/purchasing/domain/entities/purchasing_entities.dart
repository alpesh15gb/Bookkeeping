/// Domain entities for the purchasing workflow.
library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';

@immutable
class PurchaseOrderEntity {
  const PurchaseOrderEntity({
    required this.localId,
    required this.companyId,
    required this.orderDate,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.totalPaise,
    required this.syncStatus,
    required this.createdAt,
    this.remoteId,
    this.referenceNumber,
    this.description,
    this.receivedQuantity = '0',
    this.lines = const [],
    this.syncError,
  });

  final String localId;
  final String? remoteId;
  final String companyId;
  final String orderDate;
  final String? referenceNumber;
  final String supplierId;
  final String supplierName;
  final String? description;
  final int totalPaise;
  final String status;
  final String receivedQuantity;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<PurchaseOrderLineEntity> lines;
  bool get isDraft => status == 'DRAFT';
  bool get isConfirmed => status == 'CONFIRMED';
}

@immutable
class PurchaseOrderLineEntity {
  const PurchaseOrderLineEntity({
    required this.localId,
    required this.purchaseOrderLocalId,
    required this.productName,
    required this.unit,
    required this.unitPricePaise,
    required this.quantityOrdered,
    required this.totalPaise,
    required this.sortOrder,
    this.description,
    this.quantityReceived = '0',
  });
  final String localId;
  final String purchaseOrderLocalId;
  final String productName;
  final String? description;
  final String unit;
  final int unitPricePaise;
  final String quantityOrdered;
  final String quantityReceived;
  final int totalPaise;
  final int sortOrder;
}

@immutable
class PurchaseReceiptEntity {
  const PurchaseReceiptEntity({
    required this.localId,
    required this.companyId,
    required this.purchaseOrderLocalId,
    required this.receiptDate,
    required this.supplierId,
    required this.supplierName,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    this.referenceNumber,
    this.description,
    this.lines = const [],
    this.syncError,
  });
  final String localId;
  final String companyId;
  final String purchaseOrderLocalId;
  final String receiptDate;
  final String supplierId;
  final String supplierName;
  final String? referenceNumber;
  final String? description;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<PurchaseReceiptLineEntity> lines;
}

@immutable
class PurchaseReceiptLineEntity {
  const PurchaseReceiptLineEntity({
    required this.localId,
    required this.receiptLocalId,
    required this.purchaseOrderLineLocalId,
    required this.productName,
    required this.unit,
    required this.quantityReceived,
    required this.unitCostPaise,
    required this.totalPaise,
    required this.sortOrder,
  });
  final String localId;
  final String receiptLocalId;
  final String purchaseOrderLineLocalId;
  final String productName;
  final String unit;
  final String quantityReceived;
  final int unitCostPaise;
  final int totalPaise;
  final int sortOrder;
}

@immutable
class PurchaseInvoiceEntity {
  const PurchaseInvoiceEntity({
    required this.localId,
    required this.companyId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.supplierId,
    required this.supplierName,
    required this.totalBeforeTaxPaise,
    required this.taxPaise,
    required this.totalPaise,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    this.referenceNumber,
    this.description,
    this.lines = const [],
    this.syncError,
  });
  final String localId;
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
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<PurchaseInvoiceLineEntity> lines;
}

@immutable
class PurchaseInvoiceLineEntity {
  const PurchaseInvoiceLineEntity({
    required this.localId,
    required this.invoiceLocalId,
    required this.productName,
    required this.unit,
    required this.unitPricePaise,
    required this.quantity,
    required this.totalPaise,
    required this.sortOrder,
    this.description,
  });
  final String localId;
  final String invoiceLocalId;
  final String productName;
  final String? description;
  final String unit;
  final int unitPricePaise;
  final String quantity;
  final int totalPaise;
  final int sortOrder;
}
