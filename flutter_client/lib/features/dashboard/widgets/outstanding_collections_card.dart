import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/dashboard_provider.dart';

class OutstandingCollectionsCard extends StatelessWidget {
  const OutstandingCollectionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final topDebtors = dashboard.topDebtors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'OUTSTANDING COLLECTIONS',
            action: AppButton(
              label: 'View All',
              style: AppButtonStyle.ghost,
              isCompact: true,
              onPressed: () => context.go('/invoices'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (dashboard.isLoading && topDebtors.isEmpty) ...[
            const AppLoadingRow(),
            const SizedBox(height: AppSpacing.sm),
            const AppLoadingRow(),
          ] else if (topDebtors.isEmpty)
            AppEmptyState(
              icon: Icons.receipt_long,
              title: 'No outstanding',
              subtitle: 'All invoices are paid',
            )
          else
            ...topDebtors.take(5).map((debtor) {
              final name = debtor['contact_name'] ?? debtor['name'] ?? 'Unknown';
              final outstanding = double.tryParse((debtor['outstanding'] ?? debtor['total_outstanding'] ?? 0).toString()) ?? 0.0;
              final contactId = debtor['contact_id'] ?? '';

              return Column(
                children: [
                  GestureDetector(
                    onTap: contactId.isNotEmpty ? () => context.go('/parties/$contactId') : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppColors.error.withOpacity(0.1),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(name, style: AppTypography.bodyMedium),
                          ),
                          AppAmountText(
                            amount: outstanding,
                            style: AppTypography.amountTiny,
                            color: AppColors.error,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: AppSpacing.lg),
                ],
              );
            }),
          if (!dashboard.isLoading && topDebtors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Outstanding', style: AppTypography.labelLarge.copyWith(color: AppColors.gray700)),
                AppAmountText(amount: dashboard.receivables, style: AppTypography.amountMedium),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
