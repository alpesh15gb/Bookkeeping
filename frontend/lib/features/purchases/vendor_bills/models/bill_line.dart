/// Vendor bill line item — mirrors backend BillLineResponse.
library;

import 'package:flutter/foundation.dart';

@immutable
class BillLine {
  const BillLine({
    this.id,
    this.productId = '',
    this.productName,
    this.description,
    this.quantity = 1,
    this.rate = 0,
    this.discount = 0,
    this.unit = 'PCS',
    this.hsnSac = '',
    this.gstRate = 0,
    this.subtotal = 0,
    this.cgstRate = 0,
    this.cgstAmount = 0,
    this.sgstRate = 0,
    this.sgstAmount = 0,
    this.igstRate = 0,
    this.igstAmount = 0,
    this.utgstRate = 0,
    this.utgstAmount = 0,
    this.cessRate = 0,
    this.cessAmount = 0,
    this.total = 0,
  });

  final String? id;
  final String productId;
  final String? productName;
  final String? description;
  final double quantity;
  final double rate;
  final double discount;
  final String unit;
  final String hsnSac;
  final double gstRate;
  final double subtotal;
  final double cgstRate;
  final double cgstAmount;
  final double sgstRate;
  final double sgstAmount;
  final double igstRate;
  final double igstAmount;
  final double utgstRate;
  final double utgstAmount;
  final double cessRate;
  final double cessAmount;
  final double total;

  double get lineSubtotal => rate * quantity;

  /// Discount is a flat amount (not a percentage), matching the backend schema.
  double get discountAmount => discount.clamp(0, lineSubtotal);

  BillLine copyWith({
    String? id,
    String? productId,
    String? productName,
    String? description,
    double? quantity,
    double? rate,
    double? discount,
    String? unit,
    String? hsnSac,
    double? gstRate,
    double? subtotal,
    double? cgstRate,
    double? cgstAmount,
    double? sgstRate,
    double? sgstAmount,
    double? igstRate,
    double? igstAmount,
    double? utgstRate,
    double? utgstAmount,
    double? cessRate,
    double? cessAmount,
    double? total,
  }) => BillLine(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    rate: rate ?? this.rate,
    discount: discount ?? this.discount,
    unit: unit ?? this.unit,
    hsnSac: hsnSac ?? this.hsnSac,
    gstRate: gstRate ?? this.gstRate,
    subtotal: subtotal ?? this.subtotal,
    cgstRate: cgstRate ?? this.cgstRate,
    cgstAmount: cgstAmount ?? this.cgstAmount,
    sgstRate: sgstRate ?? this.sgstRate,
    sgstAmount: sgstAmount ?? this.sgstAmount,
    igstRate: igstRate ?? this.igstRate,
    igstAmount: igstAmount ?? this.igstAmount,
    utgstRate: utgstRate ?? this.utgstRate,
    utgstAmount: utgstAmount ?? this.utgstAmount,
    cessRate: cessRate ?? this.cessRate,
    cessAmount: cessAmount ?? this.cessAmount,
    total: total ?? this.total,
  );

  Map<String, dynamic> toCreatePayload() => {
    'product_id': productId,
    'quantity': quantity,
    'rate': rate,
    'discount': discount,
    'unit': unit,
    'hsn_sac': hsnSac,
    'gst_rate': gstRate,
    if (description != null) 'description': description,
  };

  factory BillLine.fromJson(Map<String, dynamic> json) => BillLine(
    id: (json['id'] ?? '').toString(),
    productId: (json['product_id'] ?? '').toString(),
    productName: json['product_name'] as String?,
    description: json['description'] as String?,
    quantity: _num(json['quantity']),
    rate: _num(json['rate']),
    discount: _num(json['discount']),
    unit: json['unit'] as String? ?? 'PCS',
    hsnSac: json['hsn_sac'] as String? ?? '',
    gstRate: _num(json['gst_rate']),
    subtotal: _num(json['subtotal']),
    cgstRate: _num(json['cgst_rate']),
    cgstAmount: _num(json['cgst_amount']),
    sgstRate: _num(json['sgst_rate']),
    sgstAmount: _num(json['sgst_amount']),
    igstRate: _num(json['igst_rate']),
    igstAmount: _num(json['igst_amount']),
    utgstRate: _num(json['utgst_rate']),
    utgstAmount: _num(json['utgst_amount']),
    cessRate: _num(json['cess_rate']),
    cessAmount: _num(json['cess_amount']),
    total: _num(json['total']),
  );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
