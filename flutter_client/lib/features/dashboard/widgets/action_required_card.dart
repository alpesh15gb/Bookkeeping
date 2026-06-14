import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/dashboard_provider.dart';

class ActionRequiredCard extends StatelessWidget {
  const ActionRequiredCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final metrics = dashboard.metrics;

    final overdueCount = _safeInt(metrics['overdue_invoices_count']);
    final pendingBills = _safeInt(metrics['pending_bills_count']);
    final totalAction = overdueCount + (pendingBills > 0 ? 1 : 0);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'ACTION REQUIRED',
            count: totalAction > 0 ? totalAction : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (dashboard.isLoading && metrics.isEmpty) ...[
            const AppLoadingRow(),
            const SizedBox(height: AppSpacing.sm),
            const AppLoadingRow(),
          ] else ...[
            if (overdueCount > 0)
              _buildActionItem(
                icon: Icons.circle,
                iconColor: AppColors.error,
                text: '$overdueCount invoice${overdueCount > 1 ? 's' : ''} overdue',
                amount: '₹${_formatAmount(dashboard.receivables)}',
                onTap: () => context.go('/invoices'),
              ),
            if (pendingBills > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildActionItem(
                icon: Icons.circle,
                iconColor: AppColors.warning,
                text: '$pendingBills bill${pendingBills > 1 ? 's' : ''} pending',
                onTap: () => context.go('/bills'),
              ),
            ],
            if (totalAction == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: AppColors.success),
                    const SizedBox(width: AppSpacing.sm),
                    Text('All caught up!', style: AppTypography.bodyMedium.copyWith(color: AppColors.success)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  int _safeInt(dynamic val) => int.tryParse((val ?? 0).toString()) ?? 0;

  String _formatAmount(double amount) {
    if (amount >= 10000000) return '${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  Widget _buildActionItem({
    required IconData icon,
    required Color iconColor,
    required String text,
    String? amount,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(icon, size: 8, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text, style: AppTypography.bodyMedium),
            ),
            if (amount != null)
              Text(
                amount,
                style: AppTypography.amountTiny.copyWith(color: AppColors.gray600),
              ),
          ],
        ),
      ),
    );
  }
}
