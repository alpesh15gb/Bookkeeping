class PaymentModel {
  final String id;
  final String? contactId;
  final String? contactName;
  final double amount;
  final String paymentDate;
  final String paymentMode;
  final String? referenceNumber;
  final String status;
  final String? notes;
  final String? invoiceId;
  final String? invoiceNumber;

  PaymentModel({
    required this.id,
    this.contactId,
    this.contactName,
    required this.amount,
    required this.paymentDate,
    required this.paymentMode,
    this.referenceNumber,
    required this.status,
    this.notes,
    this.invoiceId,
    this.invoiceNumber,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] ?? '',
      contactId: json['contact_id'],
      contactName: json['contact_name'] ?? json['contact']?['name'],
      amount: double.parse((json['amount'] ?? 0).toString()),
      paymentDate: json['payment_date'] ?? json['created_at'] ?? '',
      paymentMode: json['payment_mode'] ?? 'BANK_TRANSFER',
      referenceNumber: json['reference_number'],
      status: json['status'] ?? 'COMPLETED',
      notes: json['notes'],
      invoiceId: json['invoice_id'],
      invoiceNumber: json['invoice_number'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contact_id': contactId,
      'contact_name': contactName,
      'amount': amount,
      'payment_date': paymentDate,
      'payment_mode': paymentMode,
      'reference_number': referenceNumber,
      'status': status,
      'notes': notes,
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
    };
  }
}

class BillPaymentModel {
  final String id;
  final String? billId;
  final String? billNumber;
  final String? vendorName;
  final double amount;
  final String paymentDate;
  final String paymentMode;
  final String? referenceNumber;
  final String status;
  final String? notes;

  BillPaymentModel({
    required this.id,
    this.billId,
    this.billNumber,
    this.vendorName,
    required this.amount,
    required this.paymentDate,
    required this.paymentMode,
    this.referenceNumber,
    required this.status,
    this.notes,
  });

  factory BillPaymentModel.fromJson(Map<String, dynamic> json) {
    return BillPaymentModel(
      id: json['id'] ?? '',
      billId: json['bill_id'],
      billNumber: json['bill_number'],
      vendorName: json['vendor_name'] ?? json['contact']?['name'],
      amount: double.parse((json['amount'] ?? 0).toString()),
      paymentDate: json['payment_date'] ?? json['created_at'] ?? '',
      paymentMode: json['payment_mode'] ?? 'BANK_TRANSFER',
      referenceNumber: json['reference_number'],
      status: json['status'] ?? 'COMPLETED',
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bill_id': billId,
      'bill_number': billNumber,
      'vendor_name': vendorName,
      'amount': amount,
      'payment_date': paymentDate,
      'payment_mode': paymentMode,
      'reference_number': referenceNumber,
      'status': status,
      'notes': notes,
    };
  }
}
