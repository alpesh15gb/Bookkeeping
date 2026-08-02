/// Consistent badge component for status labels, tags, and indicators.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';
import '../tokens/status_colors.dart';
import 'package:apexbooks/features/sales/models/invoice_status.dart';

/// Size variants for badges.
enum BadgeSize { small, medium, large }

/// Style variants for badges.
enum BadgeVariant { filled, outlined, tonal }

/// A semantic badge for status, type, or category labels.
class ApexBadge extends StatelessWidget {
  const ApexBadge({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.size = BadgeSize.medium,
    this.variant = BadgeVariant.filled,
    this.onTap,
    this.borderRadius,
    this.padding,
  });

  final String label;
  final Color? color;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final BadgeSize size;
  final BadgeVariant variant;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    final bgColor = backgroundColor ?? color ?? colors.primary;
    final fgColor = textColor ?? _defaultTextColor(bgColor, colors);
    final effectivePadding = padding ?? _defaultPadding(size, isMobile);
    final effectiveRadius = borderRadius ?? BorderRadius.circular(_radiusForSize(size));

    final badge = Container(
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: _effectiveBackgroundColor(variant, bgColor, colors),
        borderRadius: effectiveRadius,
        border: variant == BadgeVariant.outlined
            ? Border.all(color: bgColor, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: _iconSize(size), color: fgColor),
            SizedBox(width: _iconGap(size)),
          ],
          Text(
            label,
            style: _textStyleForSize(size, fgColor, context),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: effectiveRadius,
        child: badge,
      );
    }

    return badge;
  }

  Color _defaultTextColor(Color bg, ApexColors colors) {
    // Simple luminance check
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? colors.textPrimary : colors.onPrimary;
  }

  Color _effectiveBackgroundColor(BadgeVariant variant, Color bg, ApexColors colors) {
    return switch (variant) {
      BadgeVariant.filled => bg,
      BadgeVariant.outlined => colors.surface,
      BadgeVariant.tonal => bg.withValues(alpha: 0.12),
    };
  }

  EdgeInsetsGeometry _defaultPadding(BadgeSize size, bool isMobile) {
    return switch (size) {
      BadgeSize.small => EdgeInsets.symmetric(
          horizontal: isMobile ? 6 : 8,
          vertical: isMobile ? 2 : 3,
        ),
      BadgeSize.medium => EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 10,
          vertical: isMobile ? 3 : 4,
        ),
      BadgeSize.large => EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 12,
          vertical: isMobile ? 4 : 6,
        ),
    };
  }

  double _radiusForSize(BadgeSize size) {
    return switch (size) {
      BadgeSize.small => 4,
      BadgeSize.medium => 6,
      BadgeSize.large => 8,
    };
  }

  double _iconSize(BadgeSize size) {
    return switch (size) {
      BadgeSize.small => 10,
      BadgeSize.medium => 12,
      BadgeSize.large => 14,
    };
  }

  double _iconGap(BadgeSize size) {
    return switch (size) {
      BadgeSize.small => 4,
      BadgeSize.medium => 5,
      BadgeSize.large => 6,
    };
  }

  TextStyle _textStyleForSize(BadgeSize size, Color color, BuildContext context) {
    final base = Theme.of(context).textTheme;
    return switch (size) {
      BadgeSize.small => base.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ) ?? TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      BadgeSize.medium => base.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ) ?? TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      BadgeSize.large => base.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ) ?? TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    };
  }
}

/// Pre-defined semantic badges for invoice statuses.
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({
    super.key,
    required this.status,
    this.size = BadgeSize.medium,
    this.showIcon = true,
  });

  final InvoiceStatus status;
  final BadgeSize size;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final statusColors = StatusColors.of(context);

    final (label, icon, bgColor, fgColor) = switch (status) {
      InvoiceStatus.draft => ('Draft', Icons.edit_outlined, statusColors.draftContainer, statusColors.draftOnContainer),
      InvoiceStatus.sent => ('Sent', Icons.send_outlined, statusColors.sentContainer, statusColors.sentOnContainer),
      InvoiceStatus.partiallyPaid => ('Partial', Icons.pending_outlined, statusColors.partialContainer, statusColors.partialOnContainer),
      InvoiceStatus.paid => ('Paid', Icons.check_circle_outlined, statusColors.paidContainer, statusColors.paidOnContainer),
      InvoiceStatus.overdue => ('Overdue', Icons.warning_amber_outlined, statusColors.overdueContainer, statusColors.overdueOnContainer),
      InvoiceStatus.cancelled => ('Cancelled', Icons.cancel_outlined, statusColors.cancelledContainer, statusColors.cancelledOnContainer),
      InvoiceStatus.posted => ('Posted', Icons.send_outlined, statusColors.partialContainer, statusColors.partialOnContainer),
    };

    return ApexBadge(
      label: label,
      icon: showIcon ? icon : null,
      backgroundColor: bgColor,
      textColor: fgColor,
      size: size,
      variant: BadgeVariant.tonal,
    );
  }
}

/// Badge for payment status.
class PaymentStatusBadge extends StatelessWidget {
  const PaymentStatusBadge({
    super.key,
    required this.status,
    this.size = BadgeSize.medium,
  });

  final PaymentStatus status;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);

    final (label, icon, bgColor, fgColor) = switch (status) {
      PaymentStatus.unpaid => ('Unpaid', Icons.close_outlined, colors.danger.withValues(alpha: 0.12), colors.danger),
      PaymentStatus.partial => ('Partial', Icons.pending_outlined, colors.warning.withValues(alpha: 0.12), colors.warning),
      PaymentStatus.paid => ('Paid', Icons.check_circle_outlined, colors.success.withValues(alpha: 0.12), colors.success),
      PaymentStatus.overpaid => ('Overpaid', Icons.info_outlined, colors.info.withValues(alpha: 0.12), colors.info),
      PaymentStatus.refunded => ('Refunded', Icons.undo_outlined, colors.textMuted.withValues(alpha: 0.12), colors.textMuted),
    };

    return ApexBadge(
      label: label,
      icon: icon,
      backgroundColor: bgColor,
      textColor: fgColor,
      size: size,
      variant: BadgeVariant.tonal,
    );
  }
}

enum PaymentStatus { unpaid, partial, paid, overpaid, refunded }