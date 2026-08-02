/// Status color tokens for consistent semantic coloring across the app.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:apexbooks/features/sales/models/invoice_status.dart';

/// Semantic status colors for badges, indicators, and state communication.
class StatusColors {
  const StatusColors._(this.context);
  final BuildContext context;

  static StatusColors of(BuildContext context) => StatusColors._(context);

  ApexColors get _c => apexColors(context);

  // ── Invoice / Document Statuses ────────────────────────────────────────────

  /// Draft - not yet finalized or sent
  Color get draft => _c.textMuted;
  Color get draftContainer => _c.surfaceMuted;
  Color get draftOnContainer => _c.textSecondary;

  /// Sent - delivered to customer
  Color get sent => _c.primary;
  Color get sentContainer => _c.primaryContainer;
  Color get sentOnContainer => _c.onPrimary;

  /// Partially paid
  Color get partial => _c.warning;
  Color get partialContainer => _c.warning.withValues(alpha: 0.12);
  Color get partialOnContainer => _c.warning;

  /// Fully paid
  Color get paid => _c.success;
  Color get paidContainer => _c.success.withValues(alpha: 0.12);
  Color get paidOnContainer => _c.success;

  /// Past due date and not fully paid
  Color get overdue => _c.danger;
  Color get overdueContainer => _c.danger.withValues(alpha: 0.12);
  Color get overdueOnContainer => _c.danger;

  /// Cancelled / voided
  Color get cancelled => _c.textMuted;
  Color get cancelledContainer => _c.surfaceMuted;
  Color get cancelledOnContainer => _c.textMuted;

  // ── Generic Statuses ──────────────────────────────────────────────────────

  Color get active => _c.success;
  Color get inactive => _c.textMuted;
  Color get pending => _c.warning;
  Color get approved => _c.success;
  Color get rejected => _c.danger;
  Color get processing => _c.info;

  // ── Helper: Get color for invoice status enum ─────────────────────────────

  Color colorForInvoiceStatus(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => draft,
      InvoiceStatus.sent => sent,
      InvoiceStatus.partiallyPaid => partial,
      InvoiceStatus.paid => paid,
      InvoiceStatus.overdue => overdue,
      InvoiceStatus.cancelled => cancelled,
      InvoiceStatus.posted => partial,
    };
  }

  Color containerForInvoiceStatus(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => draftContainer,
      InvoiceStatus.sent => sentContainer,
      InvoiceStatus.partiallyPaid => partialContainer,
      InvoiceStatus.paid => paidContainer,
      InvoiceStatus.overdue => overdueContainer,
      InvoiceStatus.cancelled => cancelledContainer,
      InvoiceStatus.posted => partialContainer,
    };
  }

  Color onContainerForInvoiceStatus(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => draftOnContainer,
      InvoiceStatus.sent => sentOnContainer,
      InvoiceStatus.partiallyPaid => partialOnContainer,
      InvoiceStatus.paid => paidOnContainer,
      InvoiceStatus.overdue => overdueOnContainer,
      InvoiceStatus.cancelled => cancelledOnContainer,
      InvoiceStatus.posted => partialOnContainer,
    };
  }
}