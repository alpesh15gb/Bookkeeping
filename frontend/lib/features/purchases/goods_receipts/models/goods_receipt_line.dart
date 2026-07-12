/// Goods receipt line — a received quantity against a PO line.
library;

import 'package:flutter/foundation.dart';

@immutable
class GoodsReceiptLine {
  const GoodsReceiptLine({
    this.id,
    this.purchaseOrderLineId = '',
    this.productId = '',
    this.productName,
    required this.quantityOrdered,
    required this.quantityReceived,
    this.warehouseId,
    this.warehouseName,
    this.lotNumber,
    this.batchNumber,
  });

  final String? id;
  final String purchaseOrderLineId;
  final String productId;
  final String? productName;
  final double quantityOrdered;
  final double quantityReceived;
  final String? warehouseId;
  final String? warehouseName;
  final String? lotNumber;
  final String? batchNumber;

  double get outstandingQuantity =>
      (quantityOrdered - quantityReceived).clamp(0, double.infinity);
  bool get isComplete => quantityReceived >= quantityOrdered;
  bool get isPartial =>
      quantityReceived > 0 && quantityReceived < quantityOrdered;
  bool get isOverReceipt => quantityReceived > quantityOrdered + 0.001;

  GoodsReceiptLine copyWith({
    String? id,
    String? purchaseOrderLineId,
    String? productId,
    String? productName,
    double? quantityOrdered,
    double? quantityReceived,
    String? warehouseId,
    String? warehouseName,
    String? lotNumber,
    String? batchNumber,
  }) => GoodsReceiptLine(
    id: id ?? this.id,
    purchaseOrderLineId: purchaseOrderLineId ?? this.purchaseOrderLineId,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    quantityOrdered: quantityOrdered ?? this.quantityOrdered,
    quantityReceived: quantityReceived ?? this.quantityReceived,
    warehouseId: warehouseId ?? this.warehouseId,
    warehouseName: warehouseName ?? this.warehouseName,
    lotNumber: lotNumber ?? this.lotNumber,
    batchNumber: batchNumber ?? this.batchNumber,
  );

  Map<String, dynamic> toCreatePayload() => {
    'purchase_order_line_id': purchaseOrderLineId,
    'product_id': productId,
    'quantity_ordered': quantityOrdered,
    'quantity_received': quantityReceived,
    if (warehouseId != null) 'warehouse_id': warehouseId,
    if (lotNumber != null) 'lot_number': lotNumber,
    if (batchNumber != null) 'batch_number': batchNumber,
  };

  factory GoodsReceiptLine.fromJson(Map<String, dynamic> json) =>
      GoodsReceiptLine(
        id: (json['id'] ?? '').toString(),
        purchaseOrderLineId: (json['purchase_order_line_id'] ?? '').toString(),
        productId: (json['product_id'] ?? '').toString(),
        productName: json['product_name'] as String?,
        quantityOrdered: _num(json['quantity_ordered']),
        quantityReceived: _num(json['quantity_received']),
        warehouseId: json['warehouse_id']?.toString(),
        warehouseName: json['warehouse_name'] as String?,
        lotNumber: json['lot_number'] as String?,
        batchNumber: json['batch_number'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
