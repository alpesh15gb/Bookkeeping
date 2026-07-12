import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import '../screens.dart';

Widget selectorWidget(
  BuildContext context,
  bool coll,
  ApexColors colors,
  String name,
) {
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: ApexSpacing.md),
    child: Container(
      padding: const EdgeInsets.all(ApexSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(ApexRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.blur_on_rounded, size: 20, color: colors.primary),
          if (!coll) ...[
            const SizedBox(width: ApexSpacing.sm),
            Expanded(
              child: Text(
                name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.unfold_more_rounded, size: 14, color: colors.textMuted),
          ],
        ],
      ),
    ),
  );
}

class HubTabWidget extends StatelessWidget {
  const HubTabWidget({super.key, required this.tabs, required this.views});
  final List<String> tabs;
  final List<Widget> views;
  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: colors.surfaceMuted,
            child: TabBar(
              isScrollable: true,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: colors.surface,
                border: Border.all(color: colors.border),
              ),
              labelColor: colors.textPrimary,
              unselectedLabelColor: colors.textSecondary,
              tabs: tabs.map((t) => Tab(height: 38, text: t)).toList(),
            ),
          ),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

List<(String, IconData, String, Widget)> getScreensList() {
  return [
    ('Dashboard', Icons.grid_view_rounded, 'OVERVIEW', const DashboardScreen()),
    (
      'Invoices',
      Icons.receipt_long_rounded,
      'TRANSACTIONS',
      const InvoiceListScreen(),
    ),
    (
      'Purchases',
      Icons.shopping_cart_outlined,
      'TRANSACTIONS',
      const HubTabWidget(
        tabs: ['Orders', 'Receipts', 'Bills', 'Payments', 'Returns'],
        views: [
          PurchaseOrderListScreen(),
          GoodsReceiptListScreen(),
          BillListScreen(),
          VendorPaymentListScreen(),
          PurchaseReturnListScreen(),
        ],
      ),
    ),
    (
      'Inventory',
      Icons.inventory_2_outlined,
      'TRANSACTIONS',
      const HubTabWidget(
        tabs: ['Stock', 'Ledger', 'Transfers', 'Adjustments', 'Warehouses'],
        views: [
          InventoryListScreen(),
          StockMovementListScreen(),
          TransferListScreen(),
          AdjustmentListScreen(),
          WarehouseListScreen(),
        ],
      ),
    ),
    (
      'Ledger',
      Icons.account_tree_outlined,
      'FINANCIALS',
      const HubTabWidget(
        tabs: ['COA', 'Journals', 'Trial Balance'],
        views: [AccountListScreen(), JournalListScreen(), TrialBalanceScreen()],
      ),
    ),
    (
      'Contacts',
      Icons.people_alt_outlined,
      'DIRECTORIES',
      const ContactListScreen(),
    ),
    (
      'Products',
      Icons.shopping_basket_outlined,
      'DIRECTORIES',
      const ProductListScreen(),
    ),
    (
      'Banking',
      Icons.account_balance_rounded,
      'FINANCIALS',
      const BankingProfileListScreen(),
    ),
    (
      'Settings',
      Icons.tune_rounded,
      'SYSTEM',
      const HubTabWidget(
        tabs: ['Taxes', 'Terms', 'Categories'],
        views: [
          TaxTemplateListScreen(),
          PaymentTermListScreen(),
          ExpenseCategoryListScreen(),
        ],
      ),
    ),
  ];
}

Widget buildProfileBox(
  BuildContext context,
  bool coll,
  ApexColors colors,
  String email,
  VoidCallback onLogout, {
  String? role,
}) {
  return Padding(
    padding: const EdgeInsets.all(ApexSpacing.md),
    child: Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: colors.primary.withValues(alpha: 0.1),
          child: Icon(Icons.person_rounded, size: 18, color: colors.primary),
        ),
        if (!coll) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email.split('@')[0],
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (role != null)
                  Text(
                    role,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: 'Log out',
            child: IconButton(
              icon:
                  Icon(Icons.logout_rounded, size: 16, color: colors.textMuted),
              onPressed: onLogout,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget buildToolbar(
  BuildContext context,
  ApexColors colors,
  String display,
  VoidCallback onSearch,
) {
  return Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: colors.surface,
      border: Border(bottom: BorderSide(color: colors.border)),
    ),
    child: Row(
      children: [
        // Prominent, keyboard-first search affordance (Ctrl/⌘+K).
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: InkWell(
                borderRadius: BorderRadius.circular(ApexRadius.md),
                onTap: onSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(ApexRadius.md),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Search invoices, customers, products…',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12.5, color: colors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _keycap('Ctrl', colors),
                      const SizedBox(width: ApexSpacing.xs),
                      _keycap('K', colors),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: ApexSpacing.lg),
        IconButton(
          icon: Icon(
            Icons.notifications_none_rounded,
            size: 20,
            color: colors.textSecondary,
          ),
          tooltip: 'Notifications',
          onPressed: () {},
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(ApexRadius.pill),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: colors.success),
              const SizedBox(width: 6),
              Text(
                display,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _keycap(String label, ApexColors colors) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: colors.surface,
    borderRadius: BorderRadius.circular(ApexRadius.sm),
    border: Border.all(color: colors.border),
  ),
  child: Text(
    label,
    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: colors.textMuted),
  ),
);
