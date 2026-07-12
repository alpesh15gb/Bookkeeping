/// Product model — matches the backend /masters/products API contract exactly.
/// Source: backend/src/schemas/master_schemas.py (ProductCreate/Update/Response)
///         and backend/src/api/v1/masters.py (list/get/create/update/delete).
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/utils/formatters.dart';

/// product_type values from the backend: GOODS or SERVICE.
enum ProductType {
  goods,
  service;

  String get apiValue => name.toUpperCase();
  static ProductType fromApi(String v) => ProductType.values.firstWhere(
    (e) => e.apiValue == v,
    orElse: () => goods,
  );

  String get displayLabel => switch (this) {
    ProductType.goods => 'Goods',
    ProductType.service => 'Service',
  };

  IconData get icon => switch (this) {
    ProductType.goods => Icons.inventory_2_outlined,
    ProductType.service => Icons.miscellaneous_services_outlined,
  };
}

/// Product — matches ProductResponse from the backend.
@immutable
class Product extends BaseModel {
  const Product({
    required this.id,
    required this.name,
    this.sku,
    this.hsnSac = '',
    this.productType = ProductType.goods,
    this.uom = 'PCS',
    this.salesPrice = 0,
    this.purchasePrice = 0,
    this.gstRate = 0,
    this.openingStock = 0,
    this.currentStock = 0,
    this.reorderLevel = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final String? sku;
  final String hsnSac;
  final ProductType productType;
  final String uom;
  final double salesPrice;
  final double purchasePrice;
  final double gstRate;
  final double openingStock;
  final double currentStock;
  final double reorderLevel;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  /// Margin percent (sales over purchase). 0 when purchase price is 0.
  double get marginPercent => purchasePrice > 0
      ? ((salesPrice - purchasePrice) / purchasePrice) * 100
      : 0;

  /// Whether current stock is at or below the reorder level (goods only).
  bool get needsReorder =>
      productType == ProductType.goods && currentStock <= reorderLevel;

  @override
  Product fromJson(Map<String, dynamic> json) => Product(
    id: (json['id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    sku: json['sku'] as String?,
    hsnSac: json['hsn_sac'] as String? ?? '',
    productType: json['product_type'] != null
        ? ProductType.fromApi(json['product_type'] as String)
        : ProductType.goods,
    uom: json['uom'] as String? ?? 'PCS',
    salesPrice: parseDecimal(json['sales_price']),
    purchasePrice: parseDecimal(json['purchase_price']),
    gstRate: parseDecimal(json['gst_rate']),
    openingStock: parseDecimal(json['opening_stock']),
    currentStock: parseDecimal(json['current_stock']),
    reorderLevel: parseDecimal(json['reorder_level']),
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  /// Serializes to the create/update payload.
  /// Only sends fields the backend accepts (ProductCreate/Update schema).
  @override
  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    if (sku != null && sku!.isNotEmpty) 'sku': sku,
    'hsn_sac': hsnSac,
    'product_type': productType.apiValue,
    'uom': uom,
    'sales_price': salesPrice.toStringAsFixed(2),
    'purchase_price': purchasePrice.toStringAsFixed(2),
    'gst_rate': gstRate.toStringAsFixed(2),
    'opening_stock': openingStock.toStringAsFixed(2),
    'reorder_level': reorderLevel.toStringAsFixed(2),
    if (!isActive) 'is_active': false,
  };

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? hsnSac,
    ProductType? productType,
    String? uom,
    double? salesPrice,
    double? purchasePrice,
    double? gstRate,
    double? openingStock,
    double? currentStock,
    double? reorderLevel,
    bool? isActive,
  }) => Product(
    id: id ?? this.id,
    name: name ?? this.name,
    sku: sku ?? this.sku,
    hsnSac: hsnSac ?? this.hsnSac,
    productType: productType ?? this.productType,
    uom: uom ?? this.uom,
    salesPrice: salesPrice ?? this.salesPrice,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    gstRate: gstRate ?? this.gstRate,
    openingStock: openingStock ?? this.openingStock,
    currentStock: currentStock ?? this.currentStock,
    reorderLevel: reorderLevel ?? this.reorderLevel,
    isActive: isActive ?? this.isActive,
  );

  @override
  String toString() => name;
}
