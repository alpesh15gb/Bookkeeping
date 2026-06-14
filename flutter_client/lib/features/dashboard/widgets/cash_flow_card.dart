import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/dashboard_provider.dart';

class CashFlowCard extends StatelessWidget {
  const CashFlowCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final cashReceived = dashboard.cashReceived;
    final totalExpenses = dashboard.totalExpenses;
    final purchases = dashboard.purchases;
    final moneyOut = totalExpenses + purchases;
    final netCash = cashReceived - moneyOut;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'CASH FLOW',
            action: AppButton(
              label: 'Cash Book',
              style: AppButtonStyle.ghost,
              isCompact: true,
              onPressed: () => context.go('/cash-book'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildFlowRow(
            label: 'Money In',
            amount: cashReceived,
            color: AppColors.success,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildFlowRow(
            label: 'Money Out',
            amount: moneyOut,
            color: AppColors.error,
          ),
          const Divider(height: AppSpacing.xl),
          _buildFlowRow(
            label: 'Net Cash',
            amount: netCash,
            color: netCash >= 0 ? AppColors.success : AppColors.error,
            isBold: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildFlowRow(
            label: 'Profit',
            amount: dashboard.netProfit,
            color: dashboard.netProfit >= 0 ? AppColors.success : AppColors.error,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFlowRow({
    required String label,
    required double amount,
    required Color color,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold
              ? AppTypography.labelLarge
              : AppTypography.bodyMedium.copyWith(color: AppColors.gray600),
        ),
        AppAmountText(
          amount: amount,
          style: isBold ? AppTypography.amountSmall : AppTypography.amountTiny,
          color: color,
        ),
      ],
    );
  }
}
