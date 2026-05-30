import 'package:flutter_client/models/contact.dart';

class BillLineModel {
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

  BillLineModel({
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

  factory BillLineModel.fromJson(Map<String, dynamic> json) {
    return BillLineModel(
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

class BillModel {
  final String id;
  final String contactId;
  final String billNumber;
  final String billDate;
  final String dueDate;
  final String status;
  final double subtotal;
  final double total;
  final double amountPaid;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double roundOff;
  final double discountTotal;
  final List<BillLineModel> lines;
  final ContactModel? contact;

  BillModel({
    required this.id,
    required this.contactId,
    required this.billNumber,
    required this.billDate,
    required this.dueDate,
    required this.status,
    required this.subtotal,
    required this.total,
    required this.amountPaid,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.roundOff,
    required this.discountTotal,
    required this.lines,
    this.contact,
  });

  factory BillModel.fromJson(Map<String, dynamic> json) {
    var rawLines = json['lines'] as List? ?? [];
    List<BillLineModel> linesList = rawLines.map((x) => BillLineModel.fromJson(x)).toList();

    return BillModel(
      id: json['id'] ?? '',
      contactId: json['contact_id'] ?? '',
      billNumber: json['bill_number'] ?? '',
      billDate: json['issue_date'] ?? '',
      dueDate: json['due_date'] ?? '',
      status: json['status'] ?? 'DRAFT',
      subtotal: double.parse((json['subtotal'] ?? 0.0).toString()),
      total: double.parse((json['total'] ?? 0.0).toString()),
      amountPaid: double.parse((json['amount_paid'] ?? 0.0).toString()),
      cgstAmount: double.parse((json['cgst_amount'] ?? 0.0).toString()),
      sgstAmount: double.parse((json['sgst_amount'] ?? 0.0).toString()),
      igstAmount: double.parse((json['igst_amount'] ?? 0.0).toString()),
      roundOff: double.parse((json['round_off'] ?? 0.0).toString()),
      discountTotal: double.parse((json['discount_total'] ?? 0.0).toString()),
      lines: linesList,
      contact: json['contact'] != null ? ContactModel.fromJson(json['contact']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contact_id': contactId,
      'bill_number': billNumber,
      'issue_date': billDate,
      'due_date': dueDate,
      'status': status,
      'subtotal': subtotal,
      'total': total,
      'amount_paid': amountPaid,
      'cgst_amount': cgstAmount,
      'sgst_amount': sgstAmount,
      'igst_amount': igstAmount,
      'round_off': roundOff,
      'discount_total': discountTotal,
      'lines': lines.map((l) => l.toJson()).toList(),
    };
  }
}
