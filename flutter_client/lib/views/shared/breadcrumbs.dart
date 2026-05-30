import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

// ═══════════════════════════════════════════════════════════════════
// BREADCRUMB NAVIGATION
// ═══════════════════════════════════════════════════════════════════

/// Data model for a single breadcrumb item.
class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;

  const BreadcrumbItem({required this.label, this.onTap});
}

/// A horizontal breadcrumb trail with "/" separators.
///
/// Items with an [BreadcrumbItem.onTap] callback are rendered as tappable
/// links in [AppColors.brandNavy]; the last item (no callback) is rendered
/// in [AppColors.textSecondary].
///
/// Horizontally scrollable on mobile screens.
class AppBreadcrumbs extends StatelessWidget {
  final List<BreadcrumbItem> items;
  final TextStyle? textStyle;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? separatorColor;

  const AppBreadcrumbs({
    super.key,
    required this.items,
    this.textStyle,
    this.activeColor,
    this.inactiveColor,
    this.separatorColor,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final active = activeColor ?? AppColors.brandNavy;
    final inactive = inactiveColor ?? AppColors.textSecondary;
    final sep = separatorColor ?? AppColors.textMuted;
    final style = textStyle ?? AppTextStyles.bodySmall;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  '/',
                  style: style.copyWith(color: sep),
                ),
              ),
            _BreadcrumbLink(
              item: items[i],
              isLast: i == items.length - 1,
              style: style,
              activeColor: active,
              inactiveColor: inactive,
            ),
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbLink extends StatelessWidget {
  final BreadcrumbItem item;
  final bool isLast;
  final TextStyle style;
  final Color activeColor;
  final Color inactiveColor;

  const _BreadcrumbLink({
    required this.item,
    required this.isLast,
    required this.style,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLast || item.onTap == null ? inactive : activeColor;
    final fontWeight = isLast ? FontWeight.w600 : FontWeight.w400;

    if (item.onTap != null) {
      return InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Text(
            item.label,
            style: style.copyWith(
              color: color,
              fontWeight: fontWeight,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: Text(
        item.label,
        style: style.copyWith(
          color: color,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}
