/// Financial year models — mirrors backend FinancialYearResponse, YearEndDashboardResponse.
library;

import 'package:flutter/foundation.dart';

/// Primary financial year model.
@immutable
class FinancialYear {
  const FinancialYear({
    required this.id,
    this.tenantId = '',
    this.name = '',
    this.startDate = '',
    this.endDate = '',
    this.status = '',
    this.isCurrent = false,
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    this.reopenReason,
    this.journalEntryId,
    this.transactionCount = 0,
    this.createdAt,
  });

  final String id;
  final String tenantId;
  final String name;
  final String startDate;
  final String endDate;
  final String status;
  final bool isCurrent;
  final String? closedAt;
  final String? closedBy;
  final String? reopenedAt;
  final String? reopenedBy;
  final String? reopenReason;
  final String? journalEntryId;
  final int transactionCount;
  final String? createdAt;

  bool get isOpen => status == 'CURRENT' || status == 'UPCOMING';
  bool get isReadyToClose => status == 'READY_TO_CLOSE';
  bool get isLocked => status == 'LOCKED';
  bool get isArchived => status == 'ARCHIVED';
  bool get canClose => status == 'CURRENT' || status == 'READY_TO_CLOSE';
  bool get canReopen => status == 'LOCKED' || status == 'ARCHIVED';

  factory FinancialYear.fromJson(Map<String, dynamic> json) => FinancialYear(
    id: (json['id'] ?? '').toString(),
    tenantId: (json['tenant_id'] ?? '').toString(),
    name: json['name'] as String? ?? '',
    startDate: json['start_date'] as String? ?? '',
    endDate: json['end_date'] as String? ?? '',
    status: json['status'] as String? ?? '',
    isCurrent: json['is_current'] as bool? ?? false,
    closedAt: json['closed_at'] as String?,
    closedBy: json['closed_by']?.toString(),
    reopenedAt: json['reopened_at'] as String?,
    reopenedBy: json['reopened_by']?.toString(),
    reopenReason: json['reopen_reason'] as String?,
    journalEntryId: json['journal_entry_id']?.toString(),
    transactionCount: json['transaction_count'] as int? ?? 0,
    createdAt: json['created_at'] as String?,
  );
}
