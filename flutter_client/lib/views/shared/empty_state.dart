import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

// ═══════════════════════════════════════════════════════════════════
// EMPTY STATE WIDGETS
// ═══════════════════════════════════════════════════════════════════

/// A centered empty state widget with icon, title, subtitle, and optional action.
///
/// Provides factory constructors for common empty-state scenarios across the app.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final Color? iconBackgroundColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.iconBackgroundColor,
  });

  /// Empty invoices list.
  factory EmptyState.invoices({VoidCallback? onAction}) {
    return EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No invoices yet',
      subtitle: 'Create your first invoice to get started.',
      actionLabel: onAction != null ? 'Create Invoice' : null,
      onAction: onAction,
      iconColor: AppColors.info,
      iconBackgroundColor: AppColors.infoBg,
    );
  }

  /// Empty contacts list.
  factory EmptyState.contacts({VoidCallback? onAction}) {
    return EmptyState(
      icon: Icons.people_outline_rounded,
      title: 'No contacts yet',
      subtitle: 'Add customers or vendors to manage your contacts.',
      actionLabel: onAction != null ? 'Add Contact' : null,
      onAction: onAction,
      iconColor: AppColors.typeCustomer,
      iconBackgroundColor: AppColors.typeCustomerBg,
    );
  }

  /// Empty products list.
  factory EmptyState.products({VoidCallback? onAction}) {
    return EmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No products yet',
      subtitle: 'Add goods or services to your product catalog.',
      actionLabel: onAction != null ? 'Add Product' : null,
      onAction: onAction,
      iconColor: AppColors.typeGoods,
      iconBackgroundColor: AppColors.typeGoodsBg,
    );
  }

  /// Empty expenses list.
  factory EmptyState.expenses({VoidCallback? onAction}) {
    return EmptyState(
      icon: Icons.account_balance_wallet_outlined,
      title: 'No expenses recorded',
      subtitle: 'Track your business expenses here.',
      actionLabel: onAction != null ? 'Add Expense' : null,
      onAction: onAction,
      iconColor: AppColors.warning,
      iconBackgroundColor: AppColors.warningBg,
    );
  }

  /// No search results found.
  factory EmptyState.noResults({String? query}) {
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No results found',
      subtitle: query != null
          ? 'No results for "$query". Try a different search term.'
          : 'Try a different search term.',
      iconColor: AppColors.textMuted,
      iconBackgroundColor: AppColors.borderLight,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconBackgroundColor ?? AppColors.borderLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 28,
                color: iconColor ?? AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
