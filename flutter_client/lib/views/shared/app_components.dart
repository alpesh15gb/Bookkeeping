import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/document_status.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/empty_state.dart';

export 'package:flutter_client/views/shared/empty_state.dart';

// ═══════════════════════════════════════════════════════════════════
// STATUS BADGE
// ═══════════════════════════════════════════════════════════════════

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? backgroundColor;

  const StatusBadge({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
  });

  factory StatusBadge.fromDocumentStatus(DocumentStatus status) {
    return StatusBadge(
      label: status.label,
      color: status.color,
      backgroundColor: status.backgroundColor,
    );
  }

  factory StatusBadge.fromInvoiceStatus(String status) {
    return StatusBadge.fromDocumentStatus(DocumentStatus.fromApi(status));
  }

  factory StatusBadge.fromContactType(String type) {
    switch (type.toUpperCase()) {
      case 'CUSTOMER':
        return StatusBadge(
          label: type,
          color: AppColors.typeCustomer,
          backgroundColor: AppColors.typeCustomerBg,
        );
      case 'VENDOR':
        return StatusBadge(
          label: type,
          color: AppColors.typeVendor,
          backgroundColor: AppColors.typeVendorBg,
        );
      default:
        return StatusBadge(
          label: type,
          color: AppColors.typeBoth,
          backgroundColor: AppColors.typeBothBg,
        );
    }
  }

  factory StatusBadge.fromProductType(String type) {
    switch (type.toUpperCase()) {
      case 'GOODS':
        return StatusBadge(
          label: type,
          color: AppColors.typeGoods,
          backgroundColor: AppColors.typeGoodsBg,
        );
      default:
        return StatusBadge(
          label: type,
          color: AppColors.typeService,
          backgroundColor: AppColors.typeServiceBg,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    final bg = backgroundColor ?? AppColors.typeDraftBg;
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.badge,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: c,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ACTION TIERS
// ═══════════════════════════════════════════════════════════════════

enum ActionTier {
  safe,
  warning,
  dangerous;

  Color get color {
    switch (this) {
      case ActionTier.safe:
        return AppColors.actionSafe;
      case ActionTier.warning:
        return AppColors.actionWarning;
      case ActionTier.dangerous:
        return AppColors.actionDangerous;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case ActionTier.safe:
        return AppColors.actionSafeBg;
      case ActionTier.warning:
        return AppColors.actionWarningBg;
      case ActionTier.dangerous:
        return AppColors.actionDangerousBg;
    }
  }

  IconData get icon {
    switch (this) {
      case ActionTier.safe:
        return Icons.save_outlined;
      case ActionTier.warning:
        return Icons.warning_amber_outlined;
      case ActionTier.dangerous:
        return Icons.delete_outline_rounded;
    }
  }
}

/// A button with explicit safety tier semantics.
///
/// Use [ActionTier.safe] for benign actions (save draft, edit note).
/// Use [ActionTier.warning] for consequential actions (finalize, approve).
/// Use [ActionTier.dangerous] for destructive actions (cancel, reverse, delete).
class ActionButton extends StatelessWidget {
  final String label;
  final ActionTier tier;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? height;

  const ActionButton({
    super.key,
    required this.label,
    required this.tier,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final h = height ?? 42.0;
    final isDangerous = tier == ActionTier.dangerous;

    if (isDangerous) {
      // Dangerous uses outlined style with explicit red
      return Semantics(
        label: '$label button, ${tier.name} action',
        button: true,
        child: SizedBox(
          height: h,
          child: OutlinedButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon ?? tier.icon, size: 16),
            label: Text(label, style: AppTextStyles.buttonSmall),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.actionDangerous,
              side: BorderSide(color: AppColors.actionDangerous.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
              textStyle: AppTextStyles.buttonSmall,
            ),
          ),
        ),
      );
    }

    if (tier == ActionTier.warning) {
      // Warning uses elevated style with amber
      return Semantics(
        label: '$label button, ${tier.name} action',
        button: true,
        child: SizedBox(
          height: h,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(icon ?? tier.icon, size: 16),
            label: Text(label),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.actionWarning,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
          ),
        ),
      );
    }

    // Safe uses the standard gold accent button
    return Semantics(
      label: '$label button, ${tier.name} action',
      button: true,
      child: SizedBox(
        height: h,
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon ?? tier.icon, size: 16),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
          ),
        ),
      ),
    );
  }
}

/// An action row that shows multiple [ActionButton]s with consistent spacing.
class ActionBar extends StatelessWidget {
  final List<Widget> children;

  const ActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// IMMUTABLE STATE INDICATORS
// ═══════════════════════════════════════════════════════════════════

/// Shown on posted / locked documents to communicate immutability.
class LockBanner extends StatelessWidget {
  final DocumentStatus status;

  const LockBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.immutableBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.immutableBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.isTerminal ? Icons.lock_rounded : Icons.lock_outline_rounded,
            size: 14,
            color: AppColors.immutableText,
          ),
          const SizedBox(width: 8),
          Text(
            status.isTerminal
                ? 'This document is ${status.label.toLowerCase()} and cannot be modified.'
                : 'This document is ${status.label.toLowerCase()} — fields are locked.',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.immutableText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlay banner for cancelled/voided documents.
class CancelledBanner extends StatelessWidget {
  const CancelledBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.statusCancelledBg,
        border: const Border(
          left: BorderSide(color: AppColors.statusCancelled, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cancel_rounded, size: 18, color: AppColors.statusCancelled),
          const SizedBox(width: 10),
          Text(
            'This document has been cancelled.',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.statusCancelled,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual wrapper that fades/grays-out content when a document is immutable.
class ImmutableWrapper extends StatelessWidget {
  final bool isLocked;
  final Widget child;

  const ImmutableWrapper({
    super.key,
    required this.isLocked,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLocked) return child;
    return Opacity(
      opacity: 0.7,
      child: AbsorbPointer(
        absorbing: true,
        child: child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STALE-STATE PROTECTION
// ═══════════════════════════════════════════════════════════════════

/// Shows when a document has been modified by another user
/// while the current user was editing it.
class ConflictWarning extends StatelessWidget {
  final VoidCallback? onRefresh;
  final String? message;

  const ConflictWarning({
    super.key,
    this.onRefresh,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.staleBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.staleBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_rounded, size: 18, color: AppColors.staleText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? 'This document has changed since you opened it.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.staleText,
              ),
            ),
          ),
          if (onRefresh != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRefresh,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.staleText,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Reload'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact version indicator — shows the optimistic-locking version number.
class VersionInfo extends StatelessWidget {
  final int? version;
  final DateTime? lastModified;

  const VersionInfo({super.key, this.version, this.lastModified});

  @override
  Widget build(BuildContext context) {
    if (version == null && lastModified == null) return const SizedBox.shrink();
    final parts = <String>[];
    if (version != null) parts.add('v$version');
    if (lastModified != null) {
      parts.add(_formatTime(lastModified!));
    }
    return Text(
      parts.join(' · '),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ═══════════════════════════════════════════════════════════════════
// AMOUNT RENDERER
// ═══════════════════════════════════════════════════════════════════

/// Renders a formatted amount with the correct [AppTextStyles] variant.
///
/// Never uses red/green — sign is shown via leading minus.
class AmountText extends StatelessWidget {
  final num value;
  final bool large;
  final bool compact;
  final bool rightAlign;
  final Color? color;

  const AmountText({
    super.key,
    required this.value,
    this.large = false,
    this.compact = false,
    this.rightAlign = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    final style = large
        ? AppTextStyles.amountLarge
        : compact
            ? AppTextStyles.amountSmall
            : AppTextStyles.amount;

    final effectiveStyle = TextStyle(
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      color: color ?? style.color,
      fontFeatures: style.fontFeatures,
      letterSpacing: style.letterSpacing,
    );

    return Text(
      AmountFormat.format(value),
      style: effectiveStyle,
      textAlign: rightAlign ? TextAlign.right : TextAlign.start,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SECTION HEADER
// ═══════════════════════════════════════════════════════════════════

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.labelSmall),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// APP CARD
// ═══════════════════════════════════════════════════════════════════

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final VoidCallback? onTap;
  final bool isLocked;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.onTap,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final card = Container(
      width: width,
      padding: padding ?? (isMobile ? AppSpacing.cardPaddingMobile : AppSpacing.cardPadding),
      margin: margin,
      decoration: BoxDecoration(
        color: isLocked ? AppColors.immutableBg : AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: isLocked ? AppColors.immutableBorder : AppColors.border),
        boxShadow: isLocked ? null : AppShadows.card,
      ),
      child: isLocked
          ? Opacity(
              opacity: 0.85,
              child: child,
            )
          : child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: card,
        ),
      );
    }
    return card;
  }
}

// ═══════════════════════════════════════════════════════════════════
// PAGE HEADER
// ═══════════════════════════════════════════════════════════════════

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBackButton;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBackButton) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h1),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// LOADING STATE
// ═══════════════════════════════════════════════════════════════════

class LoadingState extends StatelessWidget {
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(message!, style: AppTextStyles.bodySmall),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight != double.infinity;
        if (hasBoundedHeight) {
          return Center(child: content);
        }
        // Unbounded height context — give it a minimum height to center within
        return SizedBox(
          height: 300,
          child: Center(child: content),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ERROR STATE
// ═══════════════════════════════════════════════════════════════════

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 26,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: AppTextStyles.bodyMedium,
          textAlign: TextAlign.center,
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight != double.infinity;
        if (hasBoundedHeight) {
          return Center(
            child: Padding(padding: const EdgeInsets.all(40), child: content),
          );
        }
        return SizedBox(
          height: 300,
          child: Center(
            child: Padding(padding: const EdgeInsets.all(40), child: content),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CONFIRM DIALOG
// ═══════════════════════════════════════════════════════════════════

class AppConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Color? confirmColor;
  final ActionTier? tier;
  final VoidCallback onConfirm;

  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
    this.cancelLabel = 'Cancel',
    this.confirmColor,
    this.tier,
    required this.onConfirm,
  });

  /// Show a tier-aware confirmation dialog.
  ///
  /// Pass [tier] to get automatic icon/color semantics.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    Color? confirmColor,
    ActionTier tier = ActionTier.dangerous,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmColor: confirmColor,
        tier: tier,
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTier = tier ?? ActionTier.dangerous;
    final effectiveColor = confirmColor ?? effectiveTier.color;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              effectiveTier == ActionTier.safe
                  ? Icons.info_outlined
                  : effectiveTier == ActionTier.warning
                      ? Icons.warning_amber_rounded
                      : Icons.error_outline_rounded,
              size: 20,
              color: effectiveColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppTextStyles.h3)),
        ],
      ),
      content: Text(message, style: AppTextStyles.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
        ActionButton(
          label: confirmLabel,
          tier: effectiveTier,
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SUMMARY ROW
// ═══════════════════════════════════════════════════════════════════

class SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// INFO ROW
// ═══════════════════════════════════════════════════════════════════

class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AppTextStyles.bodySmall),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// QUICK ACTION BUTTON
// ═══════════════════════════════════════════════════════════════════

class QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(label, style: AppTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// METRIC CARD
// ═══════════════════════════════════════════════════════════════════

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color dotColor;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTextStyles.labelSmall),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: AppTextStyles.numericLarge),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// NEW STANDARDIZED REUSABLE COMPONENTS
// ═══════════════════════════════════════════════════════════════════

class AppStatusChip extends StatelessWidget {
  final String status;

  const AppStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color = AppColors.textMuted;
    Color bg = AppColors.typeDraftBg;
    switch (status.toUpperCase()) {
      case 'DRAFT':
        color = AppColors.statusDraft;
        bg = AppColors.statusDraftBg;
        break;
      case 'SAVED':
      case 'SYNCED':
        color = AppColors.statusPaid;
        bg = AppColors.statusPaidBg;
        break;
      case 'SUBMITTED':
      case 'APPROVED':
        color = AppColors.statusPosted;
        bg = AppColors.statusPostedBg;
        break;
      case 'PENDING':
        color = AppColors.typePending;
        bg = AppColors.typePendingBg;
        break;
      case 'CANCELLED':
        color = AppColors.statusCancelled;
        bg = AppColors.statusCancelledBg;
        break;
      case 'OVERDUE':
        color = AppColors.statusOverdue;
        bg = AppColors.statusOverdueBg;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class AppPartySelector extends StatelessWidget {
  final String label;
  final String? partyName;
  final String? gstin;
  final String? state;
  final num outstanding;
  final num creditLimit;
  final String? lastTransaction;
  final VoidCallback onTap;

  const AppPartySelector({
    super.key,
    required this.label,
    this.partyName,
    this.gstin,
    this.state,
    this.outstanding = 0,
    this.creditLimit = 0,
    this.lastTransaction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTextStyles.label.copyWith(color: AppColors.brandNavy),
              ),
              const Icon(Icons.keyboard_arrow_right, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          if (partyName != null && partyName!.isNotEmpty) ...[
            Text(
              partyName!,
              style: AppTextStyles.h2.copyWith(color: AppColors.brandNavy),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (gstin != null && gstin!.isNotEmpty) ...[
                  Text('GSTIN: $gstin', style: AppTextStyles.bodySmall),
                  const SizedBox(width: 12),
                ],
                if (state != null && state!.isNotEmpty)
                  Text('State: $state', style: AppTextStyles.bodySmall),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Outstanding', style: AppTextStyles.labelSmall),
                    const SizedBox(height: 4),
                    AmountText(value: outstanding, compact: true, rightAlign: false),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Credit Limit', style: AppTextStyles.labelSmall),
                    const SizedBox(height: 4),
                    AmountText(value: creditLimit, compact: true, rightAlign: false),
                  ],
                ),
                if (lastTransaction != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Trans', style: AppTextStyles.labelSmall),
                      const SizedBox(height: 4),
                      Text(lastTransaction!, style: AppTextStyles.numeric),
                    ],
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_outlined, color: AppColors.textMuted),
                  const SizedBox(width: 12),
                  Text(
                    'Select $label *',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AppVoucherHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String status;
  final bool isDraft;
  final VoidCallback onBackPressed;
  final List<Widget>? actions;

  const AppVoucherHeader({
    super.key,
    required this.title,
    required this.status,
    this.isDraft = false,
    required this.onBackPressed,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        onPressed: onBackPressed,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Text(title, style: AppTextStyles.h2.copyWith(color: AppColors.brandNavy)),
          const SizedBox(width: 12),
          AppStatusChip(status: status),
          if (isDraft) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: const Text(
                'DRAFT RECOVERED',
                style: TextStyle(color: AppColors.warning, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class AppAmountWidget extends StatelessWidget {
  final num value;
  final bool large;
  final Color? color;

  const AppAmountWidget({
    super.key,
    required this.value,
    this.large = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      AmountFormat.format(value),
      style: large
          ? AppTextStyles.amountLarge.copyWith(color: color ?? AppColors.brandNavy)
          : AppTextStyles.amount.copyWith(color: color ?? AppColors.brandNavy),
    );
  }
}

class AppBottomTotalBar extends StatelessWidget {
  final double subtotal;
  final double tax;
  final double total;
  final VoidCallback? onSaveDraft;
  final VoidCallback onSave;
  final bool isSaving;

  const AppBottomTotalBar({
    super.key,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.onSaveDraft,
    required this.onSave,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    final summaryWidget = Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Subtotal: ${AmountFormat.format(subtotal)} | Tax: ${AmountFormat.format(tax)}', style: AppTextStyles.caption),
            const SizedBox(height: 2),
            AppAmountWidget(value: total, large: true),
          ],
        ),
      ],
    );

    final actionsWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onSaveDraft != null) ...[
          OutlinedButton(
            onPressed: isSaving ? null : onSaveDraft,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Save Draft'),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton(
          onPressed: isSaving ? null : onSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandNavy,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save & Post'),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.elevated,
      ),
      child: isMobile
          ? SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount', style: AppTextStyles.label),
                      AppAmountWidget(value: total, large: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (onSaveDraft != null)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving ? null : onSaveDraft,
                            child: const Text('Draft'),
                          ),
                        ),
                      if (onSaveDraft != null) const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving ? null : onSave,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandNavy),
                          child: isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                summaryWidget,
                actionsWidget,
              ],
            ),
    );
  }
}

class AppSearchBar extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final TextEditingController? controller;

  const AppSearchBar({
    super.key,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: onClear != null
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: AppColors.bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class AppFilterBar extends StatelessWidget {
  final List<Widget> children;

  const AppFilterBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: children.map((w) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: w,
        )).toList(),
      ),
    );
  }
}

class AppAttachmentWidget extends StatelessWidget {
  final List<String> fileNames;
  final VoidCallback onAddAttachment;
  final ValueChanged<int>? onRemoveAttachment;

  const AppAttachmentWidget({
    super.key,
    required this.fileNames,
    required this.onAddAttachment,
    this.onRemoveAttachment,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ATTACHMENTS', style: AppTextStyles.label),
              TextButton.icon(
                onPressed: onAddAttachment,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add File'),
              ),
            ],
          ),
          if (fileNames.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No attachments yet', style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: fileNames.length,
              itemBuilder: (context, idx) => ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(fileNames[idx]),
                trailing: onRemoveAttachment != null
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () => onRemoveAttachment!(idx),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class AppDraftIndicator extends StatelessWidget {
  final VoidCallback onRecover;

  const AppDraftIndicator({super.key, required this.onRecover});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.warningBg,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Unsaved changes from a previous session detected.',
              style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: onRecover,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Recover Draft'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// NEW SHARED COMPONENT LIBRARY WIDGETS
// ═══════════════════════════════════════════════════════════════════

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hintText;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hintText,
    this.prefixIcon,
    this.validator,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      readOnly: readOnly,
      onTap: onTap,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 16) : null,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final IconData? prefixIcon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;

  const AppDropdown({
    super.key,
    this.value,
    required this.label,
    this.prefixIcon,
    required this.items,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 16) : null,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class AppDateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onTap;
  final String? Function(String?)? validator;

  const AppDateField({
    super.key,
    required this.controller,
    required this.label,
    required this.onTap,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.labelSmall.copyWith(color: AppColors.brandNavy)),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class AppSummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color? valueColor;
  final List<Widget>? children;

  const AppSummaryCard({
    super.key,
    required this.title,
    required this.value,
    this.valueColor,
    this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              AppAmountWidget(value: value, large: true, color: valueColor),
            ],
          ),
          if (children != null) ...[
            const Divider(height: 16),
            ...children!,
          ],
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class AppTaxSummary extends StatelessWidget {
  final double cgst;
  final double sgst;
  final double igst;
  final double utgst;
  final double cess;

  const AppTaxSummary({
    super.key,
    required this.cgst,
    required this.sgst,
    required this.igst,
    this.utgst = 0.0,
    this.cess = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TAX BREAKDOWN',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 12),
          SummaryRow(label: 'CGST Amount', value: AmountFormat.format(cgst)),
          SummaryRow(label: 'SGST Amount', value: AmountFormat.format(sgst)),
          SummaryRow(label: 'IGST Amount', value: AmountFormat.format(igst)),
          if (utgst.abs() > 0.001) SummaryRow(label: 'UTGST Amount', value: AmountFormat.format(utgst)),
          if (cess.abs() > 0.001) SummaryRow(label: 'Cess Amount', value: AmountFormat.format(cess)),
        ],
      ),
    );
  }
}

class AppItemGrid extends StatelessWidget {
  final List<Widget> children;
  const AppItemGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      return Column(children: children);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class AppQuickActionsBar extends StatelessWidget {
  final VoidCallback? onScanBarcode;
  final VoidCallback? onVoiceSearch;
  final VoidCallback? onAddItem;
  final VoidCallback? onDuplicateRow;
  final VoidCallback? onAttachFile;
  final VoidCallback? onShare;
  final VoidCallback? onPrint;

  const AppQuickActionsBar({
    super.key,
    this.onScanBarcode,
    this.onVoiceSearch,
    this.onAddItem,
    this.onDuplicateRow,
    this.onAttachFile,
    this.onShare,
    this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (onScanBarcode != null)
              _ActionButton(icon: Icons.qr_code_scanner_rounded, label: 'Scan Barcode', onTap: onScanBarcode!),
            if (onVoiceSearch != null)
              _ActionButton(icon: Icons.mic_rounded, label: 'Voice Search', onTap: onVoiceSearch!),
            if (onAddItem != null)
              _ActionButton(icon: Icons.add_circle_outline_rounded, label: 'Add Item', onTap: onAddItem!),
            if (onDuplicateRow != null)
              _ActionButton(icon: Icons.copy_rounded, label: 'Duplicate Row', onTap: onDuplicateRow!),
            if (onAttachFile != null)
              _ActionButton(icon: Icons.attach_file_rounded, label: 'Attach File', onTap: onAttachFile!),
            if (onShare != null)
              _ActionButton(icon: Icons.share_rounded, label: 'Share', onTap: onShare!),
            if (onPrint != null)
              _ActionButton(icon: Icons.print_rounded, label: 'Print', onTap: onPrint!),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: AppColors.brandNavy),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandNavy)),
        onPressed: onTap,
        backgroundColor: AppColors.bgLight,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
