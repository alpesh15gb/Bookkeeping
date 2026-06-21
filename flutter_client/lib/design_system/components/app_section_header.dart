import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

class AppSectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? action;
  final bool collapsed;
  final VoidCallback? onToggle;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.action,
    this.collapsed = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldStack = action != null && constraints.maxWidth < 360;

        final titleRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggle != null)
              GestureDetector(
                onTap: onToggle,
                child: Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 20,
                  color: AppColors.gray500,
                ),
              ),
            if (onToggle != null) const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                title,
                style: AppTypography.headlineSmall.copyWith(
                  color: AppColors.gray900,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: AppSpacing.sm),
              _CountBadge(count: count!),
            ],
          ],
        );

        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: action!,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleRow),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 0,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: action!,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        count.toString(),
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.gray500,
        ),
      ),
    );
  }
}
