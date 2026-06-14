import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

class AppFilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? selectedColor;

  const AppFilterChip({
    super.key,
    required this.label,
    this.count,
    this.isSelected = false,
    this.onTap,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (selectedColor ?? AppColors.primary).withOpacity(0.1)
              : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected
                ? (selectedColor ?? AppColors.primary)
                : AppColors.gray200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? (selectedColor ?? AppColors.primary)
                    : AppColors.gray600,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (selectedColor ?? AppColors.primary).withOpacity(0.2)
                      : AppColors.gray100,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  count.toString(),
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected
                        ? (selectedColor ?? AppColors.primary)
                        : AppColors.gray500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
