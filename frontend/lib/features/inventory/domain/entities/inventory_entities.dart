/// Domain entities for inventory management.
library;

import 'package:flutter/foundation.dart';
import '../../../../core/sync/sync_status.dart';

@immutable
class StockItemEntity {
  const StockItemEntity({
    required this.localId,
    required this.companyId,
    required this.name,
    required this.unit,
    required this.currentQuantity,
    this.remoteId,
    this.sku,
    this.unitCostPaise = 0,
    this.isActive = true,
    this.syncStatus = SyncStatus.synced,
    this.createdAt,
    this.updatedAt,
  });

  final String localId;
  final String? remoteId;
  final String companyId;
  final String name;
  final String? sku;
  final String unit;
  final String currentQuantity;
  final int unitCostPaise;
  final bool isActive;
  final SyncStatus syncStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get currentQtyAsDouble => double.tryParse(currentQuantity) ?? 0;
}

@immutable
class InventoryMovementEntity {
  const InventoryMovementEntity({
    required this.localId,
    required this.companyId,
    required this.stockItemId,
    required this.movementType,
    required this.quantity,
    required this.balanceAfter,
    required this.unitCostPaise,
    required this.totalPaise,
    required this.movementDate,
    required this.syncStatus,
    required this.createdAt,
    this.referenceNumber,
    this.description,
    this.syncError,
  });

  final String localId;
  final String companyId;
  final String stockItemId;
  final String movementType;
  final String quantity;
  final String balanceAfter;
  final int unitCostPaise;
  final int totalPaise;
  final String? referenceNumber;
  final String? description;
  final String movementDate;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final String? syncError;
}

@immutable
class InventoryBalanceEntity {
  const InventoryBalanceEntity({
    required this.localId,
    required this.companyId,
    required this.stockItemId,
    required this.quantityOnHand,
    required this.averageCostPaise,
    this.locationId = 'default',
  });

  final String localId;
  final String companyId;
  final String stockItemId;
  final String locationId;
  final String quantityOnHand;
  final int averageCostPaise;
}
