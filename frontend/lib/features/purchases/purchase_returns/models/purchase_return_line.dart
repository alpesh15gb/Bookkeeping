/// Purchase return line item.
library;

import 'package:flutter/foundation.dart';

@immutable
class PurchaseReturnLine {
  const PurchaseReturnLine({
    this.id,
    this.productId = '',
    this.productName,
    this.billLineId,
    this.quantityReturned = 0,
    this.maximumQuantity = 0,
    this.rate = 0,
    this.hsnSac = '',
    this.gstRate = 0,
    this.subtotal = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.total = 0,
    this.reason,
  });

  final String? id;
  final String productId;
  final String? productName;
  final String? billLineId;
  final double quantityReturned;
  final double maximumQuantity;
  final double rate;
  final String hsnSac;
  final double gstRate;
  final double subtotal;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double total;
  final String? reason;

  PurchaseReturnLine copyWith({
    String? id,
    String? productId,
    String? productName,
    String? billLineId,
    double? quantityReturned,
    double? maximumQuantity,
    double? rate,
    String? hsnSac,
    double? gstRate,
    double? subtotal,
    double? cgstAmount,
    double? sgstAmount,
    double? igstAmount,
    double? total,
    String? reason,
  }) => PurchaseReturnLine(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    billLineId: billLineId ?? this.billLineId,
    quantityReturned: quantityReturned ?? this.quantityReturned,
    maximumQuantity: maximumQuantity ?? this.maximumQuantity,
    rate: rate ?? this.rate,
    hsnSac: hsnSac ?? this.hsnSac,
    gstRate: gstRate ?? this.gstRate,
    subtotal: subtotal ?? this.subtotal,
    cgstAmount: cgstAmount ?? this.cgstAmount,
    sgstAmount: sgstAmount ?? this.sgstAmount,
    igstAmount: igstAmount ?? this.igstAmount,
    total: total ?? this.total,
    reason: reason ?? this.reason,
  );

  Map<String, dynamic> toCreatePayload() => {
    'product_id': productId,
    'quantity': quantityReturned,
    'rate': rate,
    'hsn_sac': hsnSac,
    'gst_rate': gstRate,
    'bill_line_id': billLineId,
    if (reason != null) 'description': reason,
  };

  factory PurchaseReturnLine.fromJson(Map<String, dynamic> json) =>
      PurchaseReturnLine(
        id: (json['id'] ?? '').toString(),
        productId: (json['product_id'] ?? '').toString(),
        productName: json['product_name'] as String?,
        billLineId: json['bill_line_id']?.toString(),
        quantityReturned: _num(json['quantity']),
        rate: _num(json['rate']),
        hsnSac: json['hsn_sac'] as String? ?? '',
        gstRate: _num(json['gst_rate']),
        subtotal: _num(json['subtotal']),
        cgstAmount: _num(json['cgst_amount']),
        sgstAmount: _num(json['sgst_amount']),
        igstAmount: _num(json['igst_amount']),
        total: _num(json['total']),
        reason: json['description'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
