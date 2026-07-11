/// Goods receipt header — received goods against a purchase order.
library;

import 'package:flutter/foundation.dart';
import 'goods_receipt_status.dart';
import 'goods_receipt_line.dart';

@immutable
class GoodsReceipt {
  const GoodsReceipt({
    required this.id,
    this.receiptNumber = '',
    this.purchaseOrderId = '',
    this.poNumber = '',
    this.contactId = '',
    this.contactName,
    this.receiptDate = '',
    this.status = GoodsReceiptStatus.draft,
    this.lines = const [],
    this.notes,
    this.createdAt,
  });

  final String id;
  final String receiptNumber;
  final String purchaseOrderId;
  final String poNumber;
  final String contactId;
  final String? contactName;
  final String receiptDate;
  final GoodsReceiptStatus status;
  final List<GoodsReceiptLine> lines;
  final String? notes;
  final String? createdAt;

  bool get isComplete => lines.isNotEmpty && lines.every((l) => l.isComplete);
  bool get isPartial => lines.any((l) => l.quantityReceived > 0) && !isComplete;
  double get totalReceived =>
      lines.fold<double>(0, (s, l) => s + l.quantityReceived);

  Map<String, dynamic> toCreatePayload() => {
    'purchase_order_id': purchaseOrderId,
    'receipt_date': receiptDate,
    'lines': lines.map((l) => l.toCreatePayload()).toList(),
    if (notes != null) 'notes': notes,
  };

  factory GoodsReceipt.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'] as Map<String, dynamic>?;
    return GoodsReceipt(
      id: (json['id'] ?? '').toString(),
      receiptNumber: json['receipt_number'] as String? ?? '',
      purchaseOrderId: (json['purchase_order_id'] ?? '').toString(),
      poNumber: json['po_number'] as String? ?? '',
      contactId: (json['contact_id'] ?? '').toString(),
      contactName: contact?['name'] as String?,
      receiptDate: json['receipt_date'] as String? ?? '',
      status: GoodsReceiptStatus.fromString(json['status'] as String? ?? ''),
      lines:
          (json['lines'] as List?)
              ?.map((e) => GoodsReceiptLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

@immutable
class GoodsReceiptListItem {
  const GoodsReceiptListItem({
    required this.id,
    this.receiptNumber = '',
    this.receiptDate = '',
    this.status = GoodsReceiptStatus.draft,
    this.poNumber = '',
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String receiptNumber;
  final String receiptDate;
  final GoodsReceiptStatus status;
  final String poNumber;
  final String contactName;
  final String? createdAt;

  factory GoodsReceiptListItem.fromJson(Map<String, dynamic> json) =>
      GoodsReceiptListItem(
        id: (json['id'] ?? '').toString(),
        receiptNumber: json['receipt_number'] as String? ?? '',
        receiptDate: json['receipt_date'] as String? ?? '',
        status: GoodsReceiptStatus.fromString(json['status'] as String? ?? ''),
        poNumber: json['po_number'] as String? ?? '',
        contactName: json['contact_name'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );
}
