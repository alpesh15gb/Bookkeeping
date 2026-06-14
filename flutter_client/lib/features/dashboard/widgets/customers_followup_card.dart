import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/dashboard_provider.dart';

class CustomersFollowupCard extends StatelessWidget {
  const CustomersFollowupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final topDebtors = dashboard.topDebtors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'CUSTOMERS REQUIRING FOLLOW-UP',
            action: AppButton(
              label: 'View All',
              style: AppButtonStyle.ghost,
              isCompact: true,
              onPressed: () => context.go('/parties'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (dashboard.isLoading && topDebtors.isEmpty) ...[
            const AppLoadingRow(),
            const SizedBox(height: AppSpacing.sm),
            const AppLoadingRow(),
          ] else if (topDebtors.isEmpty)
            AppEmptyState(
              icon: Icons.people_outline,
              title: 'No follow-ups needed',
              subtitle: 'All customers are up to date',
            )
          else
            ...topDebtors.take(5).map((debtor) {
              final name = debtor['contact_name'] ?? debtor['name'] ?? 'Unknown';
              final outstanding = double.tryParse((debtor['outstanding'] ?? debtor['total_outstanding'] ?? 0).toString()) ?? 0.0;
              final contactId = debtor['contact_id'] ?? '';
              final daysOverdue = _safeInt(debtor['days_overdue']);
              final isOverdue = daysOverdue > 0;

              return Column(
                children: [
                  GestureDetector(
                    onTap: contactId.isNotEmpty ? () => context.go('/parties/$contactId') : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: isOverdue
                                ? AppColors.error.withOpacity(0.1)
                                : AppColors.primary.withOpacity(0.1),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: isOverdue ? AppColors.error : AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTypography.bodyMedium),
                                if (isOverdue)
                                  Text(
                                    '$daysOverdue days overdue',
                                    style: AppTypography.labelSmall.copyWith(color: AppColors.error),
                                  ),
                              ],
                            ),
                          ),
                          AppAmountText(amount: outstanding, style: AppTypography.amountTiny),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: AppSpacing.lg),
                ],
              );
            }),
        ],
      ),
    );
  }

  int _safeInt(dynamic val) => int.tryParse((val ?? 0).toString()) ?? 0;
}
