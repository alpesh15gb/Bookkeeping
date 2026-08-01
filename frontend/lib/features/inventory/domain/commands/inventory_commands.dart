/// Commands for inventory operations.
library;

import 'package:flutter/foundation.dart';

@immutable
class CreateStockItemCommand {
  const CreateStockItemCommand({
    required this.companyId,
    required this.name,
    required this.unit,
    this.sku,
    this.unitCostPaise = 0,
    this.openingQuantity = '0',
  });

  final String companyId;
  final String name;
  final String? sku;
  final String unit;
  final int unitCostPaise;
  final String openingQuantity;
}

@immutable
class CreateMovementCommand {
  const CreateMovementCommand({
    required this.companyId,
    required this.stockItemId,
    required this.movementType,
    required this.quantity,
    required this.unitCostPaise,
    required this.movementDate,
    this.referenceNumber,
    this.description,
  });

  final String companyId;
  final String stockItemId;
  final String movementType;
  final String quantity;
  final int unitCostPaise;
  final String movementDate;
  final String? referenceNumber;
  final String? description;
}
