/// Payment and allocation models matching backend PaymentResponse/List schemas.
library;

import 'package:flutter/foundation.dart';
import 'payment_enums.dart';

// ---------------------------------------------------------------------------
// PaymentAllocation
// ---------------------------------------------------------------------------

@immutable
class PaymentAllocation {
  const PaymentAllocation({
    this.id,
    this.invoiceId = '',
    this.invoiceNumber = '',
    this.amount = 0,
  });

  final String? id;
  final String invoiceId;
  final String invoiceNumber;
  final double amount;

  PaymentAllocation copyWith({
    String? id,
    String? invoiceId,
    String? invoiceNumber,
    double? amount,
  }) => PaymentAllocation(
    id: id ?? this.id,
    invoiceId: invoiceId ?? this.invoiceId,
    invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    amount: amount ?? this.amount,
  );

  factory PaymentAllocation.fromResponse(Map<String, dynamic> json) =>
      PaymentAllocation(
        id: (json['id'] ?? '').toString(),
        invoiceId: (json['invoice_id'] ?? '').toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toCreatePayload() => {
    'invoice_id': invoiceId,
    'amount': amount,
  };
}

// ---------------------------------------------------------------------------
// Payment (full detail)
// ---------------------------------------------------------------------------

@immutable
class Payment {
  const Payment({
    required this.id,
    this.tenantId = '',
    this.contactId = '',
    this.paymentNumber = '',
    this.paymentDate = '',
    this.paymentMode = PaymentMode.other,
    this.amount = 0,
    this.referenceNumber,
    this.description,
    this.status = PaymentStatus.active,
    this.contactName = '',
    this.allocations = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String contactId;
  final String paymentNumber;
  final String paymentDate;
  final PaymentMode paymentMode;
  final double amount;
  final String? referenceNumber;
  final String? description;
  final PaymentStatus status;
  final String contactName;
  final List<PaymentAllocation> allocations;
  final String? createdAt;
  final String? updatedAt;

  double get allocatedTotal =>
      allocations.fold<double>(0, (s, a) => s + a.amount);
  double get unallocated => amount - allocatedTotal;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: (json['id'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
    contactId: (json['contact_id'] ?? '').toString(),
    paymentNumber: json['payment_number'] as String? ?? '',
    paymentDate: json['payment_date'] as String? ?? '',
    paymentMode: PaymentMode.fromString(
      json['payment_mode'] as String? ?? 'OTHER',
    ),
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    referenceNumber: json['reference_number'] as String?,
    description: json['description'] as String?,
    status: PaymentStatus.fromString(json['status'] as String? ?? 'ACTIVE'),
    contactName: json['contact_name'] as String? ?? '',
    allocations:
        (json['allocations'] as List?)
            ?.map(
              (e) => PaymentAllocation.fromResponse(e as Map<String, dynamic>),
            )
            .toList() ??
        [],
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );
}

// ---------------------------------------------------------------------------
// PaymentListItem (lightweight for list views)
// ---------------------------------------------------------------------------

@immutable
class PaymentListItem {
  const PaymentListItem({
    required this.id,
    this.paymentNumber = '',
    this.paymentDate = '',
    this.paymentMode = PaymentMode.other,
    this.amount = 0,
    this.contactName = '',
    this.status = PaymentStatus.active,
    this.createdAt,
  });

  final String id;
  final String paymentNumber;
  final String paymentDate;
  final PaymentMode paymentMode;
  final double amount;
  final String contactName;
  final PaymentStatus status;
  final String? createdAt;

  factory PaymentListItem.fromJson(Map<String, dynamic> json) =>
      PaymentListItem(
        id: (json['id'] ?? '').toString(),
        paymentNumber: json['payment_number'] as String? ?? '',
        paymentDate: json['payment_date'] as String? ?? '',
        paymentMode: PaymentMode.fromString(
          json['payment_mode'] as String? ?? 'OTHER',
        ),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        contactName: json['contact_name'] as String? ?? '',
        status: PaymentStatus.fromString(json['status'] as String? ?? 'ACTIVE'),
        createdAt: json['created_at'] as String?,
      );
}
