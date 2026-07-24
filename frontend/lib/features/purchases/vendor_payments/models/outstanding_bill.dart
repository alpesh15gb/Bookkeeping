/// Outstanding vendor bill — mirror of OutstandingInvoice for payables.
library;

import 'package:flutter/foundation.dart';

@immutable
class OutstandingBill {
  const OutstandingBill({
    required this.id,
    this.billNumber = '',
    this.total = 0,
    this.amountPaid = 0,
    this.outstandingAmount,
    this.dueDate = '',
    this.contactName = '',
    this.status = '',
  });

  final String id;
  final String billNumber;
  final double total;
  final double amountPaid;
  final double? outstandingAmount;
  final String dueDate;
  final String contactName;
  final String status;

  double get outstanding =>
      outstandingAmount ?? (total - amountPaid).clamp(0, double.infinity);
  bool get isOverdue =>
      dueDate.isNotEmpty && dueDate.compareTo(_today()) < 0 && outstanding > 0;
  bool get isClosed => outstanding <= 0;

  int get daysOverdue {
    if (dueDate.isEmpty) return 0;
    try {
      final due = DateTime.parse(dueDate);
      return DateTime.now().difference(due).inDays;
    } catch (e) {
      debugPrint('OutstandingBill.daysOverdue: invalid dueDate "$dueDate" — $e');
      return 0;
    }
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  factory OutstandingBill.fromJson(Map<String, dynamic> json) =>
      OutstandingBill(
        id: (json['id'] ?? '').toString(),
        billNumber: json['bill_number'] as String? ?? '',
        total: _num(json['total']),
        amountPaid: _num(json['amount_paid']),
        outstandingAmount: json['outstanding'] == null
            ? null
            : _num(json['outstanding']),
        dueDate: json['due_date'] as String? ?? '',
        contactName: json['contact_name'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
