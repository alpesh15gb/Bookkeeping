/// Invoice line item — matches backend InvoiceLineResponse schema.
library;

import 'package:flutter/foundation.dart';

@immutable
class InvoiceLine {
  const InvoiceLine({
    this.id,
    this.productId = '',
    this.productName,
    this.description,
    this.quantity = 1,
    this.rate = 0,
    this.discount = 0,
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
  double get discountAmount => lineSubtotal * (discount / 100);

  InvoiceLine copyWith({
    String? id,
    String? productId,
    String? productName,
    String? description,
    double? quantity,
    double? rate,
    double? discount,
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
  }) => InvoiceLine(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    rate: rate ?? this.rate,
    discount: discount ?? this.discount,
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

  /// Serialize for backend (InvoiceLineCreate shape).
  Map<String, dynamic> toCreatePayload() => {
    'product_id': productId,
    'quantity': quantity,
    'rate': rate,
    'discount': discount,
    'hsn_sac': hsnSac,
    'gst_rate': gstRate,
  };

  factory InvoiceLine.fromResponse(Map<String, dynamic> json) => InvoiceLine(
    id: (json['id'] ?? '').toString(),
    productId: (json['product_id'] ?? '').toString(),
    productName: json['product_name'] as String?,
    description: json['description'] as String?,
    quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
    rate: (json['rate'] as num?)?.toDouble() ?? 0,
    discount: (json['discount'] as num?)?.toDouble() ?? 0,
    hsnSac: json['hsn_sac'] as String? ?? '',
    gstRate: (json['gst_rate'] as num?)?.toDouble() ?? 0,
    subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    cgstRate: (json['cgst_rate'] as num?)?.toDouble() ?? 0,
    cgstAmount: (json['cgst_amount'] as num?)?.toDouble() ?? 0,
    sgstRate: (json['sgst_rate'] as num?)?.toDouble() ?? 0,
    sgstAmount: (json['sgst_amount'] as num?)?.toDouble() ?? 0,
    igstRate: (json['igst_rate'] as num?)?.toDouble() ?? 0,
    igstAmount: (json['igst_amount'] as num?)?.toDouble() ?? 0,
    utgstRate: (json['utgst_rate'] as num?)?.toDouble() ?? 0,
    utgstAmount: (json['utgst_amount'] as num?)?.toDouble() ?? 0,
    cessRate: (json['cess_rate'] as num?)?.toDouble() ?? 0,
    cessAmount: (json['cess_amount'] as num?)?.toDouble() ?? 0,
    total: (json['total'] as num?)?.toDouble() ?? 0,
  );
}
