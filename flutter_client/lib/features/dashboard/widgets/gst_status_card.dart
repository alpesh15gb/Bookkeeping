import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/dashboard_provider.dart';

class GstStatusCard extends StatelessWidget {
  const GstStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final metrics = dashboard.metrics;
    final gstLiability = dashboard.totalGstLiability;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'GST STATUS',
            action: AppButton(
              label: 'File Return',
              style: AppButtonStyle.primary,
              isCompact: true,
              onPressed: () => context.go('/gst-returns'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildStatusRow(
            label: 'GSTR-3B',
            status: 'Pending',
            dueDate: 'Due: Jul 20',
            color: AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildStatusRow(
            label: 'GSTR-1',
            status: 'Filed',
            dueDate: 'Filed: Jun 11',
            color: AppColors.success,
          ),
          const Divider(height: AppSpacing.xl),
          _buildAmountRow('Payable', gstLiability),
          const SizedBox(height: AppSpacing.sm),
          _buildAmountRow('ITC Available', double.tryParse((metrics['itc_available'] ?? 0).toString()) ?? 0.0),
        ],
      ),
    );
  }

  Widget _buildStatusRow({
    required String label,
    required String status,
    required String dueDate,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.bodyMedium),
              Text(
                dueDate,
                style: AppTypography.labelSmall.copyWith(color: AppColors.gray500),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            status,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        AppAmountText(amount: amount, style: AppTypography.amountTiny),
      ],
    );
  }
}
