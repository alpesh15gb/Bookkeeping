/// Purchase return (debit note) header.
library;

import 'package:flutter/foundation.dart';
import 'purchase_return_status.dart';
import 'purchase_return_line.dart';

@immutable
class PurchaseReturn {
  const PurchaseReturn({
    required this.id,
    this.returnNumber = '',
    this.billId,
    this.billNumber = '',
    this.contactId = '',
    this.contactName,
    this.returnDate = '',
    this.status = PurchaseReturnStatus.draft,
    this.subtotal = 0,
    this.totalTax = 0,
    this.total = 0,
    this.lines = const [],
    this.notes,
    this.createdAt,
  });

  final String id;
  final String returnNumber;
  final String? billId;
  final String billNumber;
  final String contactId;
  final String? contactName;
  final String returnDate;
  final PurchaseReturnStatus status;
  final double subtotal;
  final double totalTax;
  final double total;
  final List<PurchaseReturnLine> lines;
  final String? notes;
  final String? createdAt;

  Map<String, dynamic> toCreatePayload() => {
    if (billId != null) 'bill_id': billId,
    'return_date': returnDate,
    'lines': lines.map((l) => l.toCreatePayload()).toList(),
    if (notes != null) 'notes': notes,
  };

  factory PurchaseReturn.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'] as Map<String, dynamic>?;
    return PurchaseReturn(
      id: (json['id'] ?? '').toString(),
      returnNumber: json['return_number'] as String? ?? '',
      billId: json['bill_id']?.toString(),
      billNumber: json['bill_number'] as String? ?? '',
      contactId: (json['contact_id'] ?? '').toString(),
      contactName: contact?['name'] as String? ?? '',
      returnDate: json['return_date'] as String? ?? '',
      status: PurchaseReturnStatus.fromString(json['status'] as String? ?? ''),
      subtotal: _num(json['subtotal']),
      totalTax: _num(json['total_tax']),
      total: _num(json['total']),
      lines:
          (json['lines'] as List?)
              ?.map(
                (e) => PurchaseReturnLine.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

@immutable
class PurchaseReturnListItem {
  const PurchaseReturnListItem({
    required this.id,
    this.returnNumber = '',
    this.returnDate = '',
    this.status = PurchaseReturnStatus.draft,
    this.total = 0,
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String returnNumber;
  final String returnDate;
  final PurchaseReturnStatus status;
  final double total;
  final String contactName;
  final String? createdAt;

  factory PurchaseReturnListItem.fromJson(Map<String, dynamic> json) =>
      PurchaseReturnListItem(
        id: (json['id'] ?? '').toString(),
        returnNumber: json['return_number'] as String? ?? '',
        returnDate: json['return_date'] as String? ?? '',
        status: PurchaseReturnStatus.fromString(
          json['status'] as String? ?? '',
        ),
        total: _num(json['total']),
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
