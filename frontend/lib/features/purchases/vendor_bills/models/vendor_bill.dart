/// Vendor bill header — mirrors backend BillResponse.
library;

import 'package:flutter/foundation.dart';
import 'bill_status.dart';
import 'bill_line.dart';

@immutable
class VendorBill {
  const VendorBill({
    required this.id,
    this.billNumber = '',
    this.contactId = '',
    this.contactName,
    this.issueDate = '',
    this.dueDate = '',
    this.status = BillStatus.draft,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
    this.roundOff = 0,
    this.total = 0,
    this.amountPaid = 0,
    this.posStateCode = '',
    this.referenceNumber,
    this.notes,
    this.termsAndConditions,
    this.tdsRate = 0,
    this.tdsAmount = 0,
    this.itcEligible = true,
    this.isGstInclusive = false,
    this.lines = const [],
    this.purchaseOrderId,
    this.goodsReceiptId,
    this.createdAt,
  });

  final String id;
  final String billNumber;
  final String contactId;
  final String? contactName;
  final String issueDate;
  final String dueDate;
  final BillStatus status;
  final double subtotal;
  final double discountTotal;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double roundOff;
  final double total;
  final double amountPaid;
  final String posStateCode;
  final String? referenceNumber;
  final String? notes;
  final String? termsAndConditions;
  final double tdsRate;
  final double tdsAmount;
  final bool itcEligible;
  final bool isGstInclusive;
  final List<BillLine> lines;
  final String? purchaseOrderId;
  final String? goodsReceiptId;
  final String? createdAt;

  double get totalTax =>
      cgstAmount + sgstAmount + igstAmount + utgstAmount + cessAmount;
  double get outstanding =>
      (total - amountPaid - tdsAmount).clamp(0, double.infinity);
  bool get isPaid => amountPaid + tdsAmount >= total - 0.01;

  Map<String, dynamic> toCreatePayload() => {
    'contact_id': contactId,
    'bill_number': billNumber,
    'issue_date': issueDate,
    'due_date': dueDate,
    'pos_state_code': posStateCode,
    'line_items': lines.map((l) => l.toCreatePayload()).toList(),
    if (referenceNumber != null) 'reference_number': referenceNumber,
    if (notes != null) 'notes': notes,
    if (termsAndConditions != null) 'terms_and_conditions': termsAndConditions,
    'tds_rate': tdsRate,
    'itc_eligible': itcEligible,
    'is_gst_inclusive': isGstInclusive,
  };

  factory VendorBill.fromJson(Map<String, dynamic> json) {
    final rawContact = json['contact'];
    final contact = rawContact is Map
        ? rawContact.cast<String, dynamic>()
        : const <String, dynamic>{};
    return VendorBill(
      id: (json['id'] ?? '').toString(),
      billNumber: json['bill_number'] as String? ?? '',
      contactId: (json['contact_id'] ?? '').toString(),
      contactName:
          json['contact_name'] as String? ?? contact['name'] as String? ?? '',
      issueDate: json['issue_date'] as String? ?? '',
      dueDate: json['due_date'] as String? ?? '',
      status: BillStatus.fromString(json['status'] as String? ?? ''),
      subtotal: _num(json['subtotal']),
      discountTotal: _num(json['discount_total']),
      cgstAmount: _num(json['cgst_amount']),
      sgstAmount: _num(json['sgst_amount']),
      igstAmount: _num(json['igst_amount']),
      utgstAmount: _num(json['utgst_amount']),
      cessAmount: _num(json['cess_amount']),
      roundOff: _num(json['round_off']),
      total: _num(json['total']),
      amountPaid: _num(json['amount_paid']),
      posStateCode: json['pos_state_code'] as String? ?? '',
      referenceNumber: json['reference_number'] as String?,
      notes: json['notes'] as String?,
      termsAndConditions: json['terms_and_conditions'] as String?,
      tdsRate: _num(json['tds_rate']),
      tdsAmount: _num(json['tds_amount']),
      itcEligible: json['itc_eligible'] as bool? ?? true,
      isGstInclusive: json['is_gst_inclusive'] as bool? ?? false,
      lines:
          (json['lines'] as List?)
              ?.whereType<Map<Object?, Object?>>()
              .map((e) => BillLine.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          [],
      purchaseOrderId: json['purchase_order_id']?.toString(),
      goodsReceiptId: json['goods_receipt_id']?.toString(),
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
class VendorBillListItem {
  const VendorBillListItem({
    required this.id,
    this.billNumber = '',
    this.issueDate = '',
    this.dueDate = '',
    this.status = BillStatus.draft,
    this.total = 0,
    this.amountPaid = 0,
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String billNumber;
  final String issueDate;
  final String dueDate;
  final BillStatus status;
  final double total;
  final double amountPaid;
  final String contactName;
  final String? createdAt;

  double get outstanding => (total - amountPaid).clamp(0, double.infinity);

  factory VendorBillListItem.fromJson(Map<String, dynamic> json) =>
      VendorBillListItem(
        id: (json['id'] ?? '').toString(),
        billNumber: json['bill_number'] as String? ?? '',
        issueDate: json['issue_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        status: BillStatus.fromString(json['status'] as String? ?? ''),
        total: _num(json['total']),
        amountPaid: _num(json['amount_paid']),
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
