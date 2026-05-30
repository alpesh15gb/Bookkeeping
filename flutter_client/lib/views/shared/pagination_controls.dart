import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

// ═══════════════════════════════════════════════════════════════════
// PAGINATION CONTROLS
// ═══════════════════════════════════════════════════════════════════

/// A horizontal row with Previous / Next buttons and "Page X of Y" text.
///
/// Disables Previous on page 1 and Next on the last page.
class PaginationControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = currentPage <= 1;
    final isLast = currentPage >= totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: isFirst ? null : onPrevious,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('Previous'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isFirst ? AppColors.textMuted : AppColors.textPrimary,
            side: BorderSide(
              color: isFirst ? AppColors.borderLight : AppColors.borderInput,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            textStyle: AppTextStyles.buttonSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            'Page $currentPage of $totalPages',
            style: AppTextStyles.bodySmall,
          ),
        ),
        OutlinedButton.icon(
          onPressed: isLast ? null : onNext,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('Next'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isLast ? AppColors.textMuted : AppColors.textPrimary,
            side: BorderSide(
              color: isLast ? AppColors.borderLight : AppColors.borderInput,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            textStyle: AppTextStyles.buttonSmall,
          ),
        ),
      ],
    );
  }
}
