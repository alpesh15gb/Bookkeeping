/// Vendor payment and allocation models.
library;

import 'package:flutter/foundation.dart';
import 'vendor_payment_enums.dart';

/// A single allocation of a payment against an outstanding bill.
@immutable
class PaymentAllocation {
  const PaymentAllocation({
    this.billId = '',
    this.billNumber = '',
    required this.amount,
  });

  final String billId;
  final String billNumber;
  final double amount;

  Map<String, dynamic> toCreatePayload() => {
    'bill_id': billId,
    'amount': amount,
  };

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) =>
      PaymentAllocation(
        billId: (json['bill_id'] ?? '').toString(),
        billNumber: json['bill_number'] as String? ?? '',
        amount: _num(json['amount']),
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// Vendor payment header.
@immutable
class VendorPayment {
  const VendorPayment({
    required this.id,
    this.paymentNumber = '',
    this.contactId = '',
    this.contactName = '',
    this.paymentDate = '',
    this.paymentMode = PaymentMode.cash,
    this.amount = 0,
    this.amountAllocated = 0,
    this.referenceNumber,
    this.description,
    this.status = VendorPaymentStatus.active,
    this.allocations = const [],
    this.createdAt,
  });

  final String id;
  final String paymentNumber;
  final String contactId;
  final String contactName;
  final String paymentDate;
  final PaymentMode paymentMode;
  final double amount;
  final double amountAllocated;
  final String? referenceNumber;
  final String? description;
  final VendorPaymentStatus status;
  final List<PaymentAllocation> allocations;
  final String? createdAt;

  double get unallocatedAmount =>
      (amount - amountAllocated).clamp(0, double.infinity);
  bool get isFullyAllocated => amountAllocated >= amount - 0.01;

  Map<String, dynamic> toCreatePayload() => {
    'contact_id': contactId,
    'payment_number': paymentNumber,
    'payment_date': paymentDate,
    'payment_mode': paymentMode.value,
    'amount': amount,
    if (referenceNumber != null) 'reference_number': referenceNumber,
    if (description != null) 'description': description,
    'allocations': allocations.map((a) => a.toCreatePayload()).toList(),
  };

  factory VendorPayment.fromJson(Map<String, dynamic> json) {
    final rawContact = json['contact'];
    final contact = rawContact is Map
        ? rawContact.cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawAllocations = json['allocations'];
    final allocations = rawAllocations is List
        ? rawAllocations
              .whereType<Map>()
              .map((e) => PaymentAllocation.fromJson(e.cast<String, dynamic>()))
              .toList()
        : <PaymentAllocation>[];
    return VendorPayment(
      id: (json['id'] ?? '').toString(),
      paymentNumber: json['payment_number'] as String? ?? '',
      contactId: (json['contact_id'] ?? '').toString(),
      contactName:
          json['contact_name'] as String? ?? contact['name'] as String? ?? '',
      paymentDate: json['payment_date'] as String? ?? '',
      paymentMode: PaymentMode.fromString(
        json['payment_mode'] as String? ?? '',
      ),
      amount: _num(json['amount']),
      amountAllocated: json['amount_allocated'] == null
          ? allocations.fold<double>(0, (sum, item) => sum + item.amount)
          : _num(json['amount_allocated']),
      referenceNumber: json['reference_number'] as String?,
      description: json['description'] as String?,
      status: VendorPaymentStatus.fromString(json['status'] as String? ?? ''),
      allocations: allocations,
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
