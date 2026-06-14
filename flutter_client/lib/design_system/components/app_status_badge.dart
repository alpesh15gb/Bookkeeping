import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

enum InvoiceStatus {
  draft,
  pending,
  overdue,
  partial,
  paid,
  cancelled,
}

class AppStatusBadge extends StatelessWidget {
  final InvoiceStatus status;
  final String? additionalInfo;
  final bool isCompact;

  const AppStatusBadge({
    super.key,
    required this.status,
    this.additionalInfo,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: config.textColor,
              shape: BoxShape.circle,
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 4),
            Text(
              config.label,
              style: AppTypography.labelSmall.copyWith(color: config.textColor),
            ),
          ],
          if (additionalInfo != null && !isCompact) ...[
            const SizedBox(width: 4),
            Text(
              additionalInfo!,
              style: AppTypography.labelSmall.copyWith(
                color: config.textColor.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _StatusConfig _getStatusConfig() {
    switch (status) {
      case InvoiceStatus.draft:
        return _StatusConfig(
          label: 'Draft',
          backgroundColor: AppColors.statusDraftBg,
          textColor: AppColors.statusDraft,
        );
      case InvoiceStatus.pending:
        return _StatusConfig(
          label: 'Pending',
          backgroundColor: AppColors.statusPendingBg,
          textColor: AppColors.statusPending,
        );
      case InvoiceStatus.overdue:
        return _StatusConfig(
          label: 'Overdue',
          backgroundColor: AppColors.statusOverdueBg,
          textColor: AppColors.statusOverdue,
        );
      case InvoiceStatus.partial:
        return _StatusConfig(
          label: 'Partial',
          backgroundColor: AppColors.statusPartialBg,
          textColor: AppColors.statusPartial,
        );
      case InvoiceStatus.paid:
        return _StatusConfig(
          label: 'Paid',
          backgroundColor: AppColors.statusPaidBg,
          textColor: AppColors.statusPaid,
        );
      case InvoiceStatus.cancelled:
        return _StatusConfig(
          label: 'Cancelled',
          backgroundColor: AppColors.statusCancelledBg,
          textColor: AppColors.statusCancelled,
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _StatusConfig({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });
}
