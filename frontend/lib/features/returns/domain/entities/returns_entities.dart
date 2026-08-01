library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';

@immutable
class SalesReturnEntity {
  const SalesReturnEntity({
    required this.localId,
    required this.companyId,
    required this.returnDate,
    required this.customerId,
    required this.customerName,
    required this.totalPaise,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    this.sourceInvoiceLocalId,
    this.referenceNumber,
    this.description,
    this.lines = const [],
    this.syncError,
  });
  final String localId;
  final String companyId;
  final String returnDate;
  final String customerId;
  final String customerName;
  final String? sourceInvoiceLocalId;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<SalesReturnLineEntity> lines;
  bool get isPosted => lifecycleStatus == 'posted';
}

@immutable
class SalesReturnLineEntity {
  const SalesReturnLineEntity({
    required this.localId,
    required this.returnLocalId,
    this.sourceInvoiceLineLocalId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPricePaise,
    required this.totalPaise,
  });
  final String localId;
  final String returnLocalId;
  final String? sourceInvoiceLineLocalId;
  final String productName;
  final String unit;
  final String quantity;
  final int unitPricePaise;
  final int totalPaise;
}

@immutable
class PurchaseReturnEntity {
  const PurchaseReturnEntity({
    required this.localId,
    required this.companyId,
    required this.returnDate,
    required this.supplierId,
    required this.supplierName,
    required this.totalPaise,
    required this.lifecycleStatus,
    required this.syncStatus,
    required this.createdAt,
    this.sourceReceiptLocalId,
    this.referenceNumber,
    this.description,
    this.lines = const [],
    this.syncError,
  });
  final String localId;
  final String companyId;
  final String returnDate;
  final String supplierId;
  final String supplierName;
  final String? sourceReceiptLocalId;
  final String? referenceNumber;
  final String? description;
  final int totalPaise;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<PurchaseReturnLineEntity> lines;
}

@immutable
class PurchaseReturnLineEntity {
  const PurchaseReturnLineEntity({
    required this.localId,
    required this.returnLocalId,
    this.sourceReceiptLineLocalId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitCostPaise,
    required this.totalPaise,
  });
  final String localId;
  final String returnLocalId;
  final String? sourceReceiptLineLocalId;
  final String productName;
  final String unit;
  final String quantity;
  final int unitCostPaise;
  final int totalPaise;
}
