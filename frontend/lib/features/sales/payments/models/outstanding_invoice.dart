/// Display model for an invoice's outstanding balance and allocation status.
library;

import 'package:flutter/foundation.dart';
import 'package:apexbooks/core/utils/formatters.dart';

@immutable
class OutstandingInvoice {
  const OutstandingInvoice({
    required this.id,
    this.invoiceNumber = '',
    this.total = 0,
    this.amountPaid = 0,
    this.dueDate = '',
    this.contactName = '',
    this.status = '',
  });

  final String id;
  final String invoiceNumber;
  final double total;
  final double amountPaid;
  final String dueDate;
  final String contactName;
  final String status;

  double get outstanding => (total - amountPaid).clamp(0, double.infinity);
  bool get isOverdue =>
      dueDate.isNotEmpty && dueDate.compareTo(_today()) < 0 && outstanding > 0;
  bool get isClosed => outstanding <= 0;

  int get daysOverdue {
    if (dueDate.isEmpty) return 0;
    try {
      final due = DateTime.parse(dueDate);
      return DateTime.now().difference(due).inDays;
    } catch (e) {
      debugPrint(
        'OutstandingInvoice.daysOverdue: invalid dueDate "$dueDate" — $e',
      );
      return 0;
    }
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  factory OutstandingInvoice.fromInvoiceJson(Map<String, dynamic> json) =>
      OutstandingInvoice(
        id: (json['id'] ?? '').toString(),
        invoiceNumber: json['invoice_number'] as String? ?? '',
        total: parseDoubleSafe(json['total']),
        amountPaid: parseDoubleSafe(json['amount_paid']),
        dueDate: json['due_date'] as String? ?? '',
        contactName: json['contact_name'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );
}
