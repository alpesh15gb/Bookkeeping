import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

enum KpiTrend { up, down, neutral }

class AppKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? trendValue;
  final KpiTrend trend;
  final Color? iconColor;
  final VoidCallback? onTap;

  const AppKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trendValue,
    this.trend = KpiTrend.neutral,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.gray200),
          boxShadow: AppShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.primary).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? AppColors.primary,
                  ),
                ),
                const Spacer(),
                if (trendValue != null) _buildTrend(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.gray500,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: AppTypography.amountLarge.copyWith(
                color: AppColors.gray900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrend() {
    Color color;
    IconData icon;

    switch (trend) {
      case KpiTrend.up:
        color = AppColors.success;
        icon = Icons.arrow_upward;
        break;
      case KpiTrend.down:
        color = AppColors.error;
        icon = Icons.arrow_downward;
        break;
      case KpiTrend.neutral:
        color = AppColors.gray400;
        icon = Icons.remove;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          trendValue!,
          style: AppTypography.labelSmall.copyWith(color: color),
        ),
      ],
    );
  }
}
