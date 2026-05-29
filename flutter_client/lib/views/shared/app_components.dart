import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/document_status.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

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
    return Container(
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
      return SizedBox(
        height: h,
        child: OutlinedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon ?? tier.icon, size: 16),
          label: Text(label, style: AppTextStyles.buttonSmall),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.actionDangerous,
            side: BorderSide(color: AppColors.actionDangerous.withOpacity(0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            textStyle: AppTextStyles.buttonSmall,
          ),
        ),
      );
    }

    if (tier == ActionTier.warning) {
      // Warning uses elevated style with amber
      return SizedBox(
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
      );
    }

    // Safe uses the standard gold accent button
    return SizedBox(
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
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
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
              color: effectiveColor.withOpacity(0.1),
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
