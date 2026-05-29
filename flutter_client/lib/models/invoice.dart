import 'package:flutter_client/models/contact.dart';

class InvoiceLineModel {
  final String? id;
  final String productId;
  final String? productName;
  final double quantity;
  final double rate;
  final double discount;
  final String hsnSac;
  final double gstRate;
  final double subtotal;
  final double total;

  InvoiceLineModel({
    this.id,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.rate,
    this.discount = 0.0,
    required this.hsnSac,
    required this.gstRate,
    this.subtotal = 0.0,
    this.total = 0.0,
  });

  factory InvoiceLineModel.fromJson(Map<String, dynamic> json) {
    return InvoiceLineModel(
      id: json['id'],
      productId: json['product_id'] ?? '',
      productName: json['product_name'],
      quantity: double.parse((json['quantity'] ?? 0.0).toString()),
      rate: double.parse((json['rate'] ?? 0.0).toString()),
      discount: double.parse((json['discount'] ?? 0.0).toString()),
      hsnSac: json['hsn_sac'] ?? '',
      gstRate: double.parse((json['gst_rate'] ?? 0.0).toString()),
      subtotal: double.parse((json['subtotal'] ?? 0.0).toString()),
      total: double.parse((json['total'] ?? 0.0).toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'product_id': productId,
      'quantity': quantity,
      'rate': rate,
      'discount': discount,
      'hsn_sac': hsnSac,
      'gst_rate': gstRate,
    };
  }
}

class InvoiceModel {
  final String id;
  final String contactId;
  final String invoiceNumber;
  final String issueDate;
  final String dueDate;
  final String posStateCode;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double roundOff;
  final double total;
  final double amountPaid;
  final String? irn;
  final String? qrCode;
  final String eInvoiceStatus;
  final String? eInvoiceError;
  final List<InvoiceLineModel> lines;
  final ContactModel? contact;
  final String? notes;
  final Map<String, dynamic>? billingAddress;
  final Map<String, dynamic>? shippingAddress;
  final double utgstAmount;
  final double cessAmount;

  InvoiceModel({
    required this.id,
    required this.contactId,
    required this.invoiceNumber,
    required this.issueDate,
    required this.dueDate,
    required this.posStateCode,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.roundOff,
    required this.total,
    required this.amountPaid,
    this.irn,
    this.qrCode,
    required this.eInvoiceStatus,
    this.eInvoiceError,
    required this.lines,
    this.contact,
    this.notes,
    this.billingAddress,
    this.shippingAddress,
    this.utgstAmount = 0.0,
    this.cessAmount = 0.0,
  });

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    var rawLines = json['lines'] as List? ?? [];
    List<InvoiceLineModel> linesList = rawLines.map((x) => InvoiceLineModel.fromJson(x)).toList();

    return InvoiceModel(
      id: json['id'] ?? '',
      contactId: json['contact_id'] ?? '',
      invoiceNumber: json['invoice_number'] ?? '',
      issueDate: json['issue_date'] ?? '',
      dueDate: json['due_date'] ?? '',
      posStateCode: json['pos_state_code'] ?? '27',
      status: json['status'] ?? 'DRAFT',
      subtotal: double.parse((json['subtotal'] ?? 0.0).toString()),
      discountTotal: double.parse((json['discount_total'] ?? 0.0).toString()),
      cgstAmount: double.parse((json['cgst_amount'] ?? 0.0).toString()),
      sgstAmount: double.parse((json['sgst_amount'] ?? 0.0).toString()),
      igstAmount: double.parse((json['igst_amount'] ?? 0.0).toString()),
      roundOff: double.parse((json['round_off'] ?? 0.0).toString()),
      total: double.parse((json['total'] ?? 0.0).toString()),
      amountPaid: double.parse((json['amount_paid'] ?? 0.0).toString()),
      irn: json['irn'],
      qrCode: json['qr_code'],
      eInvoiceStatus: json['e_invoice_status'] ?? 'PENDING',
      eInvoiceError: json['e_invoice_error'],
      lines: linesList,
      contact: json['contact'] != null ? ContactModel.fromJson(json['contact']) : null,
      notes: json['notes'],
      billingAddress: json['billing_address'] is Map ? Map<String, dynamic>.from(json['billing_address']) : null,
      shippingAddress: json['shipping_address'] is Map ? Map<String, dynamic>.from(json['shipping_address']) : null,
      utgstAmount: double.parse((json['utgst_amount'] ?? 0.0).toString()),
      cessAmount: double.parse((json['cess_amount'] ?? 0.0).toString()),
    );
  }
}
