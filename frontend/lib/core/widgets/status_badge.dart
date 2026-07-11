/// Shared status/state primitives reused across every list + detail screen.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Visual tone for a [StatusBadge].
enum StatusTone { neutral, primary, success, warning, danger, info }

/// A compact pill that renders a document status (DRAFT, POSTED, PAID, ...).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final (fg, bg) = _palette(colors, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ApexRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _palette(ApexColors c, StatusTone t) {
    switch (t) {
      case StatusTone.neutral:
        return (c.textSecondary, c.surfaceMuted);
      case StatusTone.primary:
        return (c.primary, c.primaryContainer);
      case StatusTone.success:
        return (c.success, c.success.withValues(alpha: 0.12));
      case StatusTone.warning:
        return (c.warning, c.warning.withValues(alpha: 0.14));
      case StatusTone.danger:
        return (c.danger, c.danger.withValues(alpha: 0.12));
      case StatusTone.info:
        return (c.info, c.info.withValues(alpha: 0.12));
    }
  }
}

/// Maps a backend status string to a [StatusTone] for common document states.
StatusTone toneForStatus(String? status) {
  switch (status?.toUpperCase()) {
    case 'DRAFT':
    case 'PENDING':
      return StatusTone.neutral;
    case 'POSTED':
    case 'FINALIZED':
    case 'CONFIRMED':
    case 'ISSUED':
    case 'SENT':
      return StatusTone.primary;
    case 'PAID':
    case 'RECONCILED':
    case 'RECEIVED':
    case 'ACTIVE':
    case 'OPEN':
      return StatusTone.success;
    case 'PARTIAL':
    case 'OVERDUE':
    case 'PENDING_REVIEW':
      return StatusTone.warning;
    case 'CANCELLED':
    case 'VOID':
    case 'REJECTED':
    case 'CLOSED':
    case 'LOCKED':
      return StatusTone.danger;
    default:
      return StatusTone.neutral;
  }
}
