import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

/// Single source of truth for document lifecycle states.
///
/// Every document type (invoice, bill, estimate, order, note)
/// maps to this enum. UI drift is prevented by centralizing:
///   - display labels
///   - badge colors
///   - editability rules
///   - reversal/re-activation rules
///   - permitted transitions
enum DocumentStatus {
  draft,
  posted,
  partiallyPaid,
  paid,
  cancelled,
  overdue;

  // ── Display ───────────────────────────────────────────────

  String get label {
    switch (this) {
      case DocumentStatus.draft:
        return 'Draft';
      case DocumentStatus.posted:
        return 'Posted';
      case DocumentStatus.partiallyPaid:
        return 'Partial';
      case DocumentStatus.paid:
        return 'Paid';
      case DocumentStatus.cancelled:
        return 'Cancelled';
      case DocumentStatus.overdue:
        return 'Overdue';
    }
  }

  // ── Colors ────────────────────────────────────────────────

  Color get color {
    switch (this) {
      case DocumentStatus.draft:
        return AppColors.statusDraft;
      case DocumentStatus.posted:
        return AppColors.statusPosted;
      case DocumentStatus.partiallyPaid:
        return AppColors.statusPartiallyPaid;
      case DocumentStatus.paid:
        return AppColors.statusPaid;
      case DocumentStatus.cancelled:
        return AppColors.statusCancelled;
      case DocumentStatus.overdue:
        return AppColors.statusOverdue;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case DocumentStatus.draft:
        return AppColors.statusDraftBg;
      case DocumentStatus.posted:
        return AppColors.statusPostedBg;
      case DocumentStatus.partiallyPaid:
        return AppColors.statusPartiallyPaidBg;
      case DocumentStatus.paid:
        return AppColors.statusPaidBg;
      case DocumentStatus.cancelled:
        return AppColors.statusCancelledBg;
      case DocumentStatus.overdue:
        return AppColors.statusOverdueBg;
    }
  }

  IconData get icon {
    switch (this) {
      case DocumentStatus.draft:
        return Icons.edit_note_rounded;
      case DocumentStatus.posted:
        return Icons.check_circle_outline_rounded;
      case DocumentStatus.partiallyPaid:
        return Icons.payments_rounded;
      case DocumentStatus.paid:
        return Icons.check_circle_rounded;
      case DocumentStatus.cancelled:
        return Icons.cancel_outlined;
      case DocumentStatus.overdue:
        return Icons.warning_amber_rounded;
    }
  }

  // ── Behavioural rules ─────────────────────────────────────

  /// Whether users can edit or delete this document.
  bool get isEditable =>
      this == DocumentStatus.draft;

  /// Whether the document can be reversed (credit note, reversal journal).
  bool get isReversible =>
      this == DocumentStatus.posted ||
      this == DocumentStatus.partiallyPaid ||
      this == DocumentStatus.paid;

  /// Whether the document is in a terminal state.
  bool get isTerminal =>
      this == DocumentStatus.cancelled;

  /// Whether payment is still expected.
  bool get isOutstanding =>
      this == DocumentStatus.posted ||
      this == DocumentStatus.partiallyPaid ||
      this == DocumentStatus.overdue;

  /// Whether this status implies financial finality.
  bool get isLocked =>
      this == DocumentStatus.posted ||
      this == DocumentStatus.partiallyPaid ||
      this == DocumentStatus.paid ||
      this == DocumentStatus.cancelled;

  // ── Permitted transitions ─────────────────────────────────

  /// Returns the next valid statuses from this state.
  List<DocumentStatus> get permittedTransitions {
    switch (this) {
      case DocumentStatus.draft:
        return [DocumentStatus.posted, DocumentStatus.cancelled];
      case DocumentStatus.posted:
        return [DocumentStatus.partiallyPaid, DocumentStatus.paid, DocumentStatus.cancelled];
      case DocumentStatus.partiallyPaid:
        return [DocumentStatus.paid, DocumentStatus.cancelled];
      case DocumentStatus.paid:
        return [DocumentStatus.cancelled];
      case DocumentStatus.cancelled:
        return [];
      case DocumentStatus.overdue:
        return [DocumentStatus.partiallyPaid, DocumentStatus.paid, DocumentStatus.cancelled];
    }
  }

  // ── Parsing ───────────────────────────────────────────────

  static DocumentStatus fromApi(String? raw) {
    if (raw == null) return DocumentStatus.draft;
    switch (raw.toUpperCase()) {
      case 'DRAFT':
        return DocumentStatus.draft;
      case 'POSTED':
      case 'APPROVED':
      case 'CONFIRMED':
        return DocumentStatus.posted;
      case 'PARTIAL':
      case 'PARTIALLY_PAID':
      case 'PARTIALLYPAID':
        return DocumentStatus.partiallyPaid;
      case 'PAID':
      case 'SETTLED':
      case 'CLOSED':
        return DocumentStatus.paid;
      case 'CANCELLED':
      case 'CANCELED':
      case 'VOID':
        return DocumentStatus.cancelled;
      case 'OVERDUE':
      case 'DUE':
        return DocumentStatus.overdue;
      default:
        return DocumentStatus.draft;
    }
  }
}
