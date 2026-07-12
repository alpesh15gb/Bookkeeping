/// Movement reference type — identifies the source document that triggered a stock movement.
library;

enum MovementReferenceType {
  invoice('INVOICE'),
  bill('BILL'),
  adjustment('INVENTORY_ADJUSTMENT'),
  transfer('TRANSFER'),
  opening('OPENING'),
  salesReturn('SALES_RETURN'),
  purchaseReturn('PURCHASE_RETURN');

  const MovementReferenceType(this.value);
  final String value;

  static MovementReferenceType fromString(String s) => MovementReferenceType
      .values
      .firstWhere((e) => e.value == s, orElse: () => adjustment);
}

/// Direction of a stock movement.
enum MovementDirection {
  in_('IN'),
  out('OUT'),
  transfer('TRANSFER'),
  adjustment('ADJUSTMENT');

  const MovementDirection(this.value);
  final String value;
}

/// A single immutable stock movement entry (mirrors backend StockLedger).
class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.balanceQuantity,
    required this.referenceType,
    this.referenceId,
    this.rate = 0,
    this.warehouseId,
    this.createdAt,
    this.sku = '',
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double balanceQuantity;
  final MovementReferenceType referenceType;
  final String? referenceId;
  final double rate;
  final String? warehouseId;
  final String? createdAt;
  final String sku;

  MovementDirection get direction =>
      quantity >= 0 ? MovementDirection.in_ : MovementDirection.out;

  double get totalValue => quantity.abs() * rate;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
    id: (json['id'] ?? '').toString(),
    productId: (json['product_id'] ?? '').toString(),
    productName: json['product_name'] as String? ?? '',
    quantity: _toDouble(json['quantity']),
    balanceQuantity: _toDouble(json['balance_quantity']),
    referenceType: MovementReferenceType.fromString(
      json['reference_type'] as String? ?? '',
    ),
    referenceId: json['reference_id']?.toString(),
    rate: _toDouble(json['rate']),
    warehouseId: json['warehouse_id']?.toString(),
    createdAt: json['created_at'] as String?,
    sku: json['sku'] as String? ?? '',
  );

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

/// Current stock balance for a product.
class StockBalance {
  const StockBalance({
    required this.productId,
    this.productName = '',
    this.currentStock = 0,
    this.unitCost = 0,
    this.reorderLevel = 0,
    this.warehouseId,
    this.warehouseName,
  });

  final String productId;
  final String productName;
  final double currentStock;
  final double unitCost;
  final double reorderLevel;
  final String? warehouseId;
  final String? warehouseName;

  double get stockValue => currentStock * unitCost;
  bool get isLowStock => reorderLevel > 0 && currentStock <= reorderLevel;
  bool get isOutOfStock => currentStock <= 0.001;

  factory StockBalance.fromProductJson(Map<String, dynamic> json) =>
      StockBalance(
        productId: (json['id'] ?? '').toString(),
        productName: json['name'] as String? ?? '',
        currentStock: _stockToDouble(json['current_stock']),
        unitCost: _stockToDouble(
          json['unit_cost'] ?? json['purchase_price'],
        ),
        reorderLevel: _stockToDouble(json['reorder_level']),
      );

  /// Same safe double parsing used in StockMovement.
  static double _stockToDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

/// Policy for handling negative stock situations.
enum NegativeStockPolicy { allow, warn, block }
