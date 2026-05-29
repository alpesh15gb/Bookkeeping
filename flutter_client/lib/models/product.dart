class ProductModel {
  final String id;
  final String name;
  final String? sku;
  final String hsnSac;
  final String productType; // GOODS, SERVICE
  final String uom;
  final double salesPrice;
  final double purchasePrice;
  final double gstRate;
  final double openingStock;
  final double currentStock;
  final double reorderLevel;
  final bool isActive;

  ProductModel({
    required this.id,
    required this.name,
    this.sku,
    required this.hsnSac,
    required this.productType,
    required this.uom,
    required this.salesPrice,
    required this.purchasePrice,
    required this.gstRate,
    required this.openingStock,
    required this.currentStock,
    required this.reorderLevel,
    required this.isActive,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'],
      name: json['name'],
      sku: json['sku'],
      hsnSac: json['hsn_sac'] ?? '',
      productType: json['product_type'] ?? 'GOODS',
      uom: json['uom'] ?? 'PCS',
      salesPrice: _parseDouble(json['sales_price']),
      purchasePrice: _parseDouble(json['purchase_price']),
      gstRate: _parseDouble(json['gst_rate']),
      openingStock: _parseDouble(json['opening_stock']),
      currentStock: _parseDouble(json['current_stock']),
      reorderLevel: _parseDouble(json['reorder_level']),
      isActive: json['is_active'] ?? true,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    try {
      return double.parse(value.toString());
    } catch (_) {
      return 0.0;
    }
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'sku': sku,
      'hsn_sac': hsnSac,
      'product_type': productType,
      'uom': uom,
      'sales_price': salesPrice,
      'purchase_price': purchasePrice,
      'gst_rate': gstRate,
      'opening_stock': openingStock,
      'reorder_level': reorderLevel,
      'current_stock': currentStock,
      'is_active': isActive,
    };
    if (id.isNotEmpty) map['id'] = id;
    return map;
  }
}
