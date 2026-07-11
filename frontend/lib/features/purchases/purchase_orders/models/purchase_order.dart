/// Purchase order header — mirrors backend PurchaseOrderResponse.
library;

import 'package:flutter/foundation.dart';
import 'purchase_order_status.dart';
import 'purchase_order_line.dart';

@immutable
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    this.poNumber = '',
    this.contactId = '',
    this.contactName,
    this.orderDate = '',
    this.dueDate = '',
    this.status = PurchaseOrderStatus.draft,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
    this.total = 0,
    this.amountReceived = 0,
    this.posStateCode = '',
    this.lines = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String poNumber;
  final String contactId;
  final String? contactName;
  final String orderDate;
  final String dueDate;
  final PurchaseOrderStatus status;
  final double subtotal;
  final double discountTotal;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double total;
  final double amountReceived;
  final String posStateCode;
  final List<PurchaseOrderLine> lines;
  final String? createdAt;
  final String? updatedAt;

  double get totalTax =>
      cgstAmount + sgstAmount + igstAmount + utgstAmount + cessAmount;
  bool get isFullyReceived =>
      lines.isNotEmpty && lines.every((l) => l.isFullyReceived);
  bool get isPartiallyReceived =>
      lines.any((l) => l.quantityReceived > 0) && !isFullyReceived;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'] as Map<String, dynamic>?;
    return PurchaseOrder(
      id: (json['id'] ?? '').toString(),
      poNumber: json['po_number'] as String? ?? '',
      contactId: (json['contact_id'] ?? '').toString(),
      contactName: contact?['name'] as String? ?? '',
      orderDate: json['order_date'] as String? ?? '',
      dueDate: json['due_date'] as String? ?? '',
      status: PurchaseOrderStatus.fromString(json['status'] as String? ?? ''),
      subtotal: _num(json['subtotal']),
      discountTotal: _num(json['discount_total']),
      cgstAmount: _num(json['cgst_amount']),
      sgstAmount: _num(json['sgst_amount']),
      igstAmount: _num(json['igst_amount']),
      utgstAmount: _num(json['utgst_amount']),
      cessAmount: _num(json['cess_amount']),
      total: _num(json['total']),
      amountReceived: _num(json['amount_received']),
      posStateCode: json['pos_state_code'] as String? ?? '',
      lines:
          (json['lines'] as List?)
              ?.map(
                (e) => PurchaseOrderLine.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toCreatePayload() => {
    'contact_id': contactId,
    'po_number': poNumber,
    'order_date': orderDate,
    'due_date': dueDate,
    'pos_state_code': posStateCode,
    'line_items': lines.map((l) => l.toCreatePayload()).toList(),
  };

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// Lightweight list item for table views.
@immutable
class PurchaseOrderListItem {
  const PurchaseOrderListItem({
    required this.id,
    this.poNumber = '',
    this.orderDate = '',
    this.dueDate = '',
    this.status = PurchaseOrderStatus.draft,
    this.total = 0,
    this.amountReceived = 0,
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String poNumber;
  final String orderDate;
  final String dueDate;
  final PurchaseOrderStatus status;
  final double total;
  final double amountReceived;
  final String contactName;
  final String? createdAt;

  factory PurchaseOrderListItem.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderListItem(
        id: (json['id'] ?? '').toString(),
        poNumber: json['po_number'] as String? ?? '',
        orderDate: json['order_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        status: PurchaseOrderStatus.fromString(json['status'] as String? ?? ''),
        total: _num(json['total']),
        amountReceived: _num(json['amount_received']),
        contactName: json['contact_name'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
