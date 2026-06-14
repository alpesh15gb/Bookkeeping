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
    return Row(
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
        Text(
          title,
          style: AppTypography.headlineSmall.copyWith(
            color: AppColors.gray900,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
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
          ),
        ],
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}
