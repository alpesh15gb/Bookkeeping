/// Full Invoice response model — matches backend InvoiceResponse schema.
library;

import 'package:flutter/foundation.dart';
import 'package:apexbooks/core/utils/formatters.dart';
import 'invoice_status.dart';
import 'invoice_line.dart';
import '../payments/models/payment_models.dart';

@immutable
class Invoice {
  const Invoice({
    required this.id,
    this.tenantId = '',
    this.contactId = '',
    this.invoiceNumber = '',
    this.issueDate = '',
    this.dueDate = '',
    this.status = InvoiceStatus.draft,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.shippingCharges = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.utgstAmount = 0,
    this.cessAmount = 0,
    this.roundOff = 0,
    this.total = 0,
    this.amountPaid = 0,
    this.posStateCode = '',
    this.irn,
    this.qrCode,
    this.eInvoiceStatus = EInvoiceStatus.pending,
    this.eInvoiceError,
    this.notes,
    this.termsAndConditions,
    this.referenceNumber,
    this.salesPersonId,
    this.isGstInclusive = false,
    this.isRcm = false,
    this.supplyType = 'DOMESTIC',
    this.currency = 'INR',
    this.exchangeRate = 1,
    this.tdsRate = 0,
    this.tdsAmount = 0,
    this.tcsRate = 0,
    this.tcsAmount = 0,
    this.contactName,
    this.lines = const [],
    this.originStateCode,
    this.payments = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String contactId;
  final String invoiceNumber;
  final String issueDate;
  final String dueDate;
  final InvoiceStatus status;
  final double subtotal;
  final double discountTotal;
  final double shippingCharges;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double utgstAmount;
  final double cessAmount;
  final double roundOff;
  final double total;
  final double amountPaid;
  final String posStateCode;
  final String? irn;
  final String? qrCode;
  final EInvoiceStatus eInvoiceStatus;
  final String? eInvoiceError;
  final String? notes;
  final String? termsAndConditions;
  final String? referenceNumber;
  final String? salesPersonId;
  final bool isGstInclusive;
  final bool isRcm;
  final String supplyType;
  final String currency;
  final double exchangeRate;
  final double tdsRate;
  final double tdsAmount;
  final double tcsRate;
  final double tcsAmount;
  final String? contactName;
  final List<InvoiceLine> lines;
  final String? originStateCode;
  final List<Payment> payments;
  final String? createdAt;
  final String? updatedAt;

  double get outstandingAmount => total - amountPaid;
  double get outstanding => total - amountPaid;
  String? get customerName => contactName;
  double get netAmount => subtotal - discountTotal + shippingCharges;
  double get totalTax =>
      cgstAmount + sgstAmount + igstAmount + utgstAmount + cessAmount;

  /// Parses a full Invoice from a backend InvoiceResponse JSON map.
  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: (json['id'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
    contactId: (json['contact_id'] ?? '').toString(),
    invoiceNumber: json['invoice_number'] as String? ?? '',
    issueDate: json['issue_date'] as String? ?? '',
    dueDate: json['due_date'] as String? ?? '',
    status: InvoiceStatus.fromString(json['status'] as String? ?? 'DRAFT'),
    subtotal: parseDoubleSafe(json['subtotal']),
    discountTotal: parseDoubleSafe(json['discount_total']),
    shippingCharges: parseDoubleSafe(json['shipping_charges']),
    cgstAmount: parseDoubleSafe(json['cgst_amount']),
    sgstAmount: parseDoubleSafe(json['sgst_amount']),
    igstAmount: parseDoubleSafe(json['igst_amount']),
    utgstAmount: parseDoubleSafe(json['utgst_amount']),
    cessAmount: parseDoubleSafe(json['cess_amount']),
    roundOff: parseDoubleSafe(json['round_off']),
    total: parseDoubleSafe(json['total']),
    amountPaid: parseDoubleSafe(json['amount_paid']),
    posStateCode: json['pos_state_code'] as String? ?? '',
    irn: json['irn'] as String?,
    qrCode: json['qr_code'] as String?,
    eInvoiceStatus: EInvoiceStatus.fromString(
      json['e_invoice_status'] as String? ?? 'PENDING',
    ),
    eInvoiceError: json['e_invoice_error'] as String?,
    notes: json['notes'] as String?,
    termsAndConditions: json['terms_and_conditions'] as String?,
    referenceNumber: json['reference_number'] as String?,
    salesPersonId: (json['sales_person_id'] ?? '').toString(),
    isGstInclusive: json['is_gst_inclusive'] as bool? ?? false,
    isRcm: json['is_rcm'] as bool? ?? false,
    supplyType: json['supply_type'] as String? ?? 'DOMESTIC',
    currency: json['currency'] as String? ?? 'INR',
    exchangeRate: parseDoubleSafe(json['exchange_rate'], defaultValue: 1),
    tdsRate: parseDoubleSafe(json['tds_rate']),
    tdsAmount: parseDoubleSafe(json['tds_amount']),
    tcsRate: parseDoubleSafe(json['tcs_rate']),
    tcsAmount: parseDoubleSafe(json['tcs_amount']),
    contactName:
        json['contact_name'] as String? ??
        _contactNameFromContact(json['contact']),
    lines:
        (json['lines'] as List?)
            ?.map((e) => InvoiceLine.fromResponse(e as Map<String, dynamic>))
            .toList() ??
        [],
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  /// The invoice detail response embeds the customer as `contact: {...}`
  /// rather than a flat `contact_name` field. Fall back to it so the detail
  /// view can still display the customer name.
  static String? _contactNameFromContact(Object? contact) {
    if (contact is Map && contact['name'] is String) {
      return contact['name'] as String;
    }
    return null;
  }
}

/// Lightweight list item — matches backend InvoiceListResponse.
@immutable
class InvoiceListItem {
  const InvoiceListItem({
    required this.id,
    this.contactId = '',
    this.invoiceNumber = '',
    this.issueDate = '',
    this.dueDate = '',
    this.status = InvoiceStatus.draft,
    this.total = 0,
    this.amountPaid = 0,
    this.contactName = '',
    this.referenceNumber,
    this.createdAt,
  });

  final String id;
  final String contactId;
  final String invoiceNumber;
  final String issueDate;
  final String dueDate;
  final InvoiceStatus status;
  final double total;
  final double amountPaid;
  final String contactName;
  final String? referenceNumber;
  final String? createdAt;

  double get outstanding => total - amountPaid;
  double get outstandingAmount => total - amountPaid;
  String get customerName => contactName;

  factory InvoiceListItem.fromJson(Map<String, dynamic> json) =>
      InvoiceListItem(
        id: (json['id'] ?? '').toString(),
        contactId: (json['contact_id'] ?? '').toString(),
        invoiceNumber: json['invoice_number'] as String? ?? '',
        issueDate: json['issue_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        status: InvoiceStatus.fromString(json['status'] as String? ?? 'DRAFT'),
        total: parseDoubleSafe(json['total']),
        amountPaid: parseDoubleSafe(json['amount_paid']),
        contactName: json['contact_name'] as String? ?? '',
        referenceNumber: json['reference_number'] as String?,
        createdAt: json['created_at'] as String?,
      );
}
