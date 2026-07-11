/// Dashboard data models — each maps to one backend endpoint response.
library;

import 'package:flutter/foundation.dart';

/// KPIs from GET /dashboard/kpis
@immutable
class DashboardKpis {
  const DashboardKpis({
    this.totalInvoiced = 0,
    this.totalCollected = 0,
    this.totalExpenses = 0,
    this.outstanding = 0,
    this.overdue = 0,
    this.netProfit = 0,
  });

  final double totalInvoiced;
  final double totalCollected;
  final double totalExpenses;
  final double outstanding;
  final double overdue;
  final double netProfit;

  factory DashboardKpis.fromJson(Map<String, dynamic> json) => DashboardKpis(
    totalInvoiced: (json['total_invoiced'] as num?)?.toDouble() ?? 0,
    totalCollected: (json['total_collected'] as num?)?.toDouble() ?? 0,
    totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0,
    outstanding: (json['outstanding'] as num?)?.toDouble() ?? 0,
    overdue: (json['overdue'] as num?)?.toDouble() ?? 0,
    netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0,
  );
}

/// GST metrics from GET /dashboard/metrics
@immutable
class DashboardMetrics {
  const DashboardMetrics({
    this.cgstTotal = 0,
    this.sgstTotal = 0,
    this.igstTotal = 0,
    this.cessTotal = 0,
  });

  final double cgstTotal;
  final double sgstTotal;
  final double igstTotal;
  final double cessTotal;

  double get gstTotal => cgstTotal + sgstTotal + igstTotal + cessTotal;

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) =>
      DashboardMetrics(
        cgstTotal: (json['cgst_total'] as num?)?.toDouble() ?? 0,
        sgstTotal: (json['sgst_total'] as num?)?.toDouble() ?? 0,
        igstTotal: (json['igst_total'] as num?)?.toDouble() ?? 0,
        cessTotal: (json['cess_total'] as num?)?.toDouble() ?? 0,
      );
}

/// One point on a revenue/expense trend chart.
@immutable
class TrendPoint {
  const TrendPoint({required this.month, required this.year, this.total = 0});
  final int month;
  final int year;
  final double total;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    month: json['month'] as int? ?? 1,
    year: json['year'] as int? ?? DateTime.now().year,
    total: (json['total'] as num?)?.toDouble() ?? 0,
  );

  /// Label like "Jan 2025"
  String get label {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = month.clamp(1, 12) - 1;
    return '${months[m]} $year';
  }
}

/// An overdue invoice alert from GET /dashboard/overdue-alerts
@immutable
class OverdueAlert {
  const OverdueAlert({
    required this.id,
    this.invoiceNumber = '',
    this.contactName = '',
    this.balance = 0,
    this.dueDate = '',
    this.daysOverdue = 0,
    this.severity = 'medium',
  });

  final String id;
  final String invoiceNumber;
  final String contactName;
  final double balance;
  final String dueDate;
  final int daysOverdue;
  final String severity; // "medium", "high", "critical"

  factory OverdueAlert.fromJson(Map<String, dynamic> json) => OverdueAlert(
    id: (json['id'] ?? '').toString(),
    invoiceNumber: json['invoice_number'] as String? ?? '',
    contactName: json['contact_name'] as String? ?? '',
    balance: (json['balance'] as num?)?.toDouble() ?? 0,
    dueDate: json['due_date'] as String? ?? '',
    daysOverdue: json['days_overdue'] as int? ?? 0,
    severity: json['severity'] as String? ?? 'medium',
  );
}

/// Overdue alerts response envelope.
@immutable
class OverdueAlertsResponse {
  const OverdueAlertsResponse({
    this.alerts = const [],
    this.totalOverdueAmount = 0,
    this.count = 0,
  });

  final List<OverdueAlert> alerts;
  final double totalOverdueAmount;
  final int count;

  factory OverdueAlertsResponse.fromJson(Map<String, dynamic> json) =>
      OverdueAlertsResponse(
        alerts:
            (json['alerts'] as List?)
                ?.map((e) => OverdueAlert.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalOverdueAmount:
            (json['total_overdue_amount'] as num?)?.toDouble() ?? 0,
        count: json['count'] as int? ?? 0,
      );
}
