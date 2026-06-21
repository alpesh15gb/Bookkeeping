import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

enum AppButtonStyle { primary, secondary, ghost, danger }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonStyle style;
  final IconData? icon;
  final bool isLoading;
  final bool isCompact;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = AppButtonStyle.primary,
    this.icon,
    this.isLoading = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: isCompact ? 32 : 40,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: _getButtonStyle(),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    label,
                    style: isCompact
                        ? AppTypography.labelMedium
                        : AppTypography.labelLarge,
                  ),
                ],
              ),
      ),
    );
  }

  ButtonStyle _getButtonStyle() {
    switch (style) {
      case AppButtonStyle.primary:
        return ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
      case AppButtonStyle.secondary:
        return ElevatedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.gray700,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: AppColors.gray200),
          ),
        );
      case AppButtonStyle.ghost:
        return ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.primary,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
      case AppButtonStyle.danger:
        return ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
    }
  }
}
