import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/models/auth.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/dashboard/sales_dashboard_view.dart';
import 'package:flutter_client/views/invoices/invoice_list_view.dart';
import 'package:flutter_client/views/products/product_list_view.dart';
import 'package:flutter_client/views/contacts/contact_list_view.dart';
import 'package:flutter_client/views/estimates/estimate_list_view.dart';
import 'package:flutter_client/views/expenses/expense_list_view.dart';
import 'package:flutter_client/views/bills/bill_list_view.dart';
import 'package:flutter_client/views/credit_notes/credit_note_list_view.dart';
import 'package:flutter_client/views/purchase_orders/order_list_view.dart';
import 'package:flutter_client/views/accounting/journal_entry_view.dart';
import 'package:flutter_client/views/accounting/statement_view.dart';
import 'package:flutter_client/views/payments/payment_list_view.dart';
import 'package:flutter_client/views/accounting/account_list_view.dart';
import 'package:flutter_client/views/einvoice/eway_bill_list_view.dart';
import 'package:flutter_client/views/reports/report_list_view.dart';
import 'package:flutter_client/views/settings/settings_view.dart';
import 'package:flutter_client/views/bank_reconciliation/bank_reconciliation_list_view.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_list_view.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_list_view.dart';
import 'package:flutter_client/views/audit/audit_log_list_view.dart';
import 'package:flutter_client/views/reminders/reminder_list_view.dart';
import 'package:flutter_client/views/vyapar_import/vyapar_import_view.dart';
import 'package:flutter_client/views/sales_analytics/sales_analytics_view.dart';
import 'package:flutter_client/views/banking/banking_profile_list_view.dart';

class MenuItem {
  final String name;
  final IconData icon;
  final Widget view;

  const MenuItem({
    required this.name,
    required this.icon,
    required this.view,
  });
}

final List<MenuItem> _menuItems = [
  MenuItem(name: 'Dashboard', icon: Icons.dashboard_rounded, view: const SalesDashboardView()),
  MenuItem(name: 'Invoices', icon: Icons.description_rounded, view: const InvoiceListView()),
  MenuItem(name: 'Estimates', icon: Icons.request_quote_rounded, view: const EstimateListView()),
  MenuItem(name: 'Vendor Bills', icon: Icons.receipt_rounded, view: const BillListView()),
  MenuItem(name: 'Expenses', icon: Icons.money_off_rounded, view: const ExpenseListView()),
  MenuItem(name: 'Credit/Debit Notes', icon: Icons.compare_arrows_rounded, view: const CreditNoteListView()),
  MenuItem(name: 'Orders (PO/SO)', icon: Icons.shopping_cart_rounded, view: const OrderListView()),
  MenuItem(name: 'Parties', icon: Icons.people_rounded, view: const ContactListView()),
  MenuItem(name: 'Inventory', icon: Icons.inventory_2_rounded, view: const ProductListView()),
  MenuItem(name: 'Del. Challans', icon: Icons.local_shipping_rounded, view: const DeliveryChallanListView()),
  MenuItem(name: 'Inventory Adj.', icon: Icons.inventory_2_rounded, view: const InventoryAdjustmentListView()),
  MenuItem(name: 'Journal Entry', icon: Icons.book_rounded, view: const JournalEntryView()),
  MenuItem(name: 'Payments', icon: Icons.payments_rounded, view: const PaymentListView()),
  MenuItem(name: 'Bank Recon.', icon: Icons.account_balance_outlined, view: const BankReconciliationListView()),
  MenuItem(name: 'Banking', icon: Icons.account_balance_wallet_outlined, view: const BankingProfileListView()),
  MenuItem(name: 'Chart of Accounts', icon: Icons.account_balance_rounded, view: const AccountListView()),
  MenuItem(name: 'E-Way Bills', icon: Icons.local_shipping_outlined, view: const EwayBillListView()),
  MenuItem(name: 'Sales Analytics', icon: Icons.analytics_rounded, view: const SalesAnalyticsView()),
  MenuItem(name: 'Reports', icon: Icons.bar_chart_rounded, view: const ReportListView()),
  MenuItem(name: 'Statements', icon: Icons.assessment_rounded, view: const StatementView()),
  MenuItem(name: 'Audit Log', icon: Icons.history_rounded, view: const AuditLogListView()),
  MenuItem(name: 'Reminders', icon: Icons.notifications_outlined, view: const ReminderListView()),
  MenuItem(name: 'Vyapar Import', icon: Icons.file_upload_outlined, view: const VyaparImportView()),
  MenuItem(name: 'Settings', icon: Icons.settings_rounded, view: const SettingsView()),
];

class ShellView extends StatefulWidget {
  const ShellView({super.key});

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  int _selectedIndex = 0;

  Widget get _currentView => _menuItems[_selectedIndex].view;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return AdaptiveLayout(
      mobile: _buildMobileLayout(user),
      desktop: _buildDesktopLayout(user),
    );
  }

  // ─── Desktop Layout ─────────────────────────────────────────
  Widget _buildDesktopLayout(UserResponse? user) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (i) => setState(() => _selectedIndex = i),
            user: user,
            onLogout: () => context.read<AuthProvider>().logout(),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: _menuItems[_selectedIndex].name),
                Expanded(
                  key: ValueKey(_selectedIndex),
                  child: _currentView,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mobile Layout ──────────────────────────────────────────
  Widget _buildMobileLayout(UserResponse? user) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 22),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        title: Text(_menuItems[_selectedIndex].name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: () => context.read<AuthProvider>().logout(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      drawer: _MobileDrawer(
        selectedIndex: _selectedIndex,
        onItemSelected: (i) {
          setState(() => _selectedIndex = i);
          Navigator.pop(context);
        },
        user: user,
        onLogout: () => context.read<AuthProvider>().logout(),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: _currentView,
        ),
      ),
    );
  }
}

// ─── Sidebar ────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final UserResponse? user;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.user,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.bgSidebar,
      child: Column(
        children: [
          // Brand Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.goldAccent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.menu_book_rounded, size: 20, color: AppColors.brandNavy),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apex Books',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Accounting Suite',
                      style: TextStyle(
                        color: AppColors.textWhiteMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Navigation
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _menuItems.length,
              itemBuilder: (context, i) {
                final isSelected = selectedIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onItemSelected(i),
                      borderRadius: AppRadius.sidebar,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.goldAccent : Colors.transparent,
                          borderRadius: AppRadius.sidebar,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _menuItems[i].icon,
                              size: 18,
                              color: isSelected ? AppColors.brandNavy : AppColors.textWhiteMuted,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _menuItems[i].name,
                              style: TextStyle(
                                color: isSelected ? AppColors.brandNavy : Colors.white,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // User Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white12)),
              color: AppColors.brandNavyDark,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.goldAccent,
                      child: Text(
                        user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: AppColors.brandNavy,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              color: AppColors.textWhiteMuted,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: onLogout,
                  borderRadius: AppRadius.sidebar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.sidebar,
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, size: 14, color: AppColors.textWhiteMuted),
                        SizedBox(width: 8),
                        Text(
                          'Sign Out',
                          style: TextStyle(
                            color: AppColors.textWhiteMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top Bar ────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;

  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.h3),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Text(
              'FY 2026-27',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile Drawer ──────────────────────────────────────────────
class _MobileDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final UserResponse? user;
  final VoidCallback onLogout;

  const _MobileDrawer({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.user,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.bgSidebar,
      child: SafeArea(
        child: Column(
          children: [
            // Brand header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.goldAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.menu_book_rounded, size: 18, color: AppColors.brandNavy),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Apex Books', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 1),
                      Text('Accounting Suite', style: TextStyle(color: AppColors.textWhiteMuted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Navigation items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _menuItems.length,
                itemBuilder: (context, i) {
                  final isSelected = selectedIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onItemSelected(i),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.goldAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(_menuItems[i].icon, size: 20, color: isSelected ? AppColors.brandNavy : AppColors.textWhiteMuted),
                              const SizedBox(width: 12),
                              Text(_menuItems[i].name, style: TextStyle(
                                color: isSelected ? AppColors.brandNavy : Colors.white,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // User & Sign out
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
                color: AppColors.brandNavyDark,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.goldAccent,
                        child: Text(
                          user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: AppColors.brandNavy, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.fullName ?? 'User', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(user?.email ?? '', style: const TextStyle(color: AppColors.textWhiteMuted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: onLogout,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, size: 14, color: AppColors.textWhiteMuted),
                          SizedBox(width: 8),
                          Text('Sign Out', style: TextStyle(color: AppColors.textWhiteMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
