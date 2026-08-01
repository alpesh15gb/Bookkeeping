/// Domain entities for sales fulfillment.
library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';

@immutable
class SalesOrderEntity {
  const SalesOrderEntity({
    required this.localId,
    required this.companyId,
    required this.orderDate,
    required this.customerId,
    required this.customerName,
    required this.status,
    required this.totalPaise,
    required this.syncStatus,
    required this.createdAt,
    this.remoteId,
    this.referenceNumber,
    this.description,
    this.lines = const [],
    this.syncError,
  });
  final String localId;
  final String? remoteId;
  final String companyId;
  final String orderDate;
  final String? referenceNumber;
  final String customerId;
  final String customerName;
  final String? description;
  final String status;
  final int totalPaise;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<SalesOrderLineEntity> lines;
  bool get isDraft => status == 'DRAFT';
}

@immutable
class SalesOrderLineEntity {
  const SalesOrderLineEntity({
    required this.localId,
    required this.salesOrderLocalId,
    required this.productName,
    required this.unit,
    required this.unitPricePaise,
    required this.quantityOrdered,
    required this.totalPaise,
    required this.sortOrder,
    this.description,
    this.quantityDelivered = '0',
    this.quantityInvoiced = '0',
  });
  final String localId;
  final String salesOrderLocalId;
  final String productName;
  final String? description;
  final String unit;
  final int unitPricePaise;
  final String quantityOrdered;
  final String quantityDelivered;
  final String quantityInvoiced;
  final int totalPaise;
  final int sortOrder;
}

@immutable
class SalesDeliveryEntity {
  const SalesDeliveryEntity({
    required this.localId,
    required this.companyId,
    required this.salesOrderLocalId,
    required this.deliveryDate,
    required this.customerId,
    required this.customerName,
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
  final String salesOrderLocalId;
  final String deliveryDate;
  final String customerId;
  final String customerName;
  final String? referenceNumber;
  final String? description;
  final String lifecycleStatus;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
  final List<SalesDeliveryLineEntity> lines;
}

@immutable
class SalesDeliveryLineEntity {
  const SalesDeliveryLineEntity({
    required this.localId,
    required this.deliveryLocalId,
    required this.salesOrderLineLocalId,
    required this.productName,
    required this.unit,
    required this.quantityDelivered,
    required this.unitPricePaise,
    required this.totalPaise,
    required this.sortOrder,
  });
  final String localId;
  final String deliveryLocalId;
  final String salesOrderLineLocalId;
  final String productName;
  final String unit;
  final String quantityDelivered;
  final int unitPricePaise;
  final int totalPaise;
  final int sortOrder;
}
