import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/providers/theme_provider.dart';
import 'package:flutter_client/core/sync_manager.dart';
import 'package:flutter_client/models/auth.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/global_search.dart';
import 'package:flutter_client/views/dashboard/sales_dashboard_view.dart';
import 'package:flutter_client/views/invoices/invoice_list_view.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
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
import 'package:flutter_client/views/returns/returns_list_view.dart';
import 'package:flutter_client/views/tools/backup_restore_view.dart';

// ─── Offline Banner Widget ────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final SyncManager syncManager;
  const _OfflineBanner({required this.syncManager});

  @override
  Widget build(BuildContext context) {
    final isOffline = !syncManager.isOnline;
    final pending = syncManager.pendingCount;

    Color bgColor;
    Color textColor;
    IconData icon;
    String text;

    if (isOffline && pending > 0) {
      bgColor = const Color(0xFFFFF3E0);
      textColor = const Color(0xFFE65100);
      icon = Icons.cloud_off;
      text = 'Offline — $pending change${pending == 1 ? '' : 's'} queued';
    } else if (isOffline) {
      bgColor = const Color(0xFFF2F2F4);
      textColor = const Color(0xFF5F6572);
      icon = Icons.cloud_off;
      text = 'Working offline';
    } else if (pending > 0) {
      bgColor = const Color(0xFFFFF8E1);
      textColor = const Color(0xFFF57F17);
      icon = Icons.sync;
      text = 'Syncing $pending item${pending == 1 ? '' : 's'}...';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
            ),
          ),
          if (!isOffline && pending > 0)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
            ),
        ],
      ),
    );
  }
}

// ─── Menu Data Model ──────────────────────────────────────────

class _MenuItem {
  final String name;
  final IconData icon;
  final Widget view;

  const _MenuItem({required this.name, required this.icon, required this.view});
}

class _MenuGroupDef {
  final String label;
  final IconData icon;
  final List<int> childIndices;

  const _MenuGroupDef({required this.label, required this.icon, required this.childIndices});
}

class _MenuLeaf extends _MenuEntry {
  final int index;
  const _MenuLeaf({required this.index});
}

class _MenuGroupEntry extends _MenuEntry {
  final _MenuGroupDef group;
  const _MenuGroupEntry(this.group);
}

class _MenuEntry {
  const _MenuEntry();
}

// ─── Flat view list (index matches _currentView) ───────────────
final List<_MenuItem> _flatItems = [
  _MenuItem(name: 'Dashboard', icon: Icons.dashboard_rounded, view: const SalesDashboardView()),
  _MenuItem(name: 'Invoices', icon: Icons.description_rounded, view: const InvoiceListView()),
  _MenuItem(name: 'Estimates', icon: Icons.request_quote_rounded, view: const EstimateListView()),
  _MenuItem(name: 'Sales Orders', icon: Icons.receipt_long_outlined, view: const OrderListView(orderType: 'sales')),
  _MenuItem(name: 'Credit/Debit Notes', icon: Icons.compare_arrows_rounded, view: const CreditNoteListView()),
  _MenuItem(name: 'Sales Analytics', icon: Icons.analytics_rounded, view: const SalesAnalyticsView()),
  _MenuItem(name: 'Vendor Bills', icon: Icons.receipt_rounded, view: const BillListView()),
  _MenuItem(name: 'Expenses', icon: Icons.money_off_rounded, view: const ExpenseListView()),
  _MenuItem(name: 'Purchase Orders', icon: Icons.shopping_cart_outlined, view: const OrderListView(orderType: 'purchase')),
  _MenuItem(name: 'Parties', icon: Icons.people_rounded, view: const ContactListView()),
  _MenuItem(name: 'Products', icon: Icons.inventory_2_rounded, view: const ProductListView()),
  _MenuItem(name: 'Del. Challans', icon: Icons.local_shipping_rounded, view: const DeliveryChallanListView()),
  _MenuItem(name: 'Inventory Adj.', icon: Icons.tune_rounded, view: const InventoryAdjustmentListView()),
  _MenuItem(name: 'Journal Entry', icon: Icons.book_rounded, view: const JournalEntryView()),
  _MenuItem(name: 'Payments', icon: Icons.payments_rounded, view: const PaymentListView()),
  _MenuItem(name: 'Bank Recon.', icon: Icons.account_balance_outlined, view: const BankReconciliationListView()),
  _MenuItem(name: 'Banking', icon: Icons.account_balance_wallet_outlined, view: const BankingProfileListView()),
  _MenuItem(name: 'Chart of Accounts', icon: Icons.account_balance_rounded, view: const AccountListView()),
  _MenuItem(name: 'Reports', icon: Icons.bar_chart_rounded, view: const ReportListView()),
  _MenuItem(name: 'Statements', icon: Icons.assessment_rounded, view: const StatementView()),
  _MenuItem(name: 'E-Way Bills', icon: Icons.local_shipping_outlined, view: const EwayBillListView()),
  _MenuItem(name: 'Audit Log', icon: Icons.history_rounded, view: const AuditLogListView()),
  _MenuItem(name: 'Reminders', icon: Icons.notifications_outlined, view: const ReminderListView()),
  _MenuItem(name: 'Returns', icon: Icons.assignment_return_rounded, view: const ReturnsListView()),
  _MenuItem(name: 'Vyapar Import', icon: Icons.file_upload_outlined, view: const VyaparImportView()),
  _MenuItem(name: 'Backup/Restore', icon: Icons.backup_rounded, view: const BackupRestoreView()),
  _MenuItem(name: 'Settings', icon: Icons.settings_rounded, view: const SettingsView()),
];

// ─── Grouped sidebar structure ────────────────────────────────
final List<_MenuEntry> _sidebarEntries = [
  const _MenuLeaf(index: 0), // Dashboard
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Sales',
    icon: Icons.point_of_sale_rounded,
    childIndices: [1, 2, 3, 4, 5], // Invoices, Estimates, Sales Orders, C/D Notes, Sales Analytics
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Purchases',
    icon: Icons.shopping_bag_outlined,
    childIndices: [6, 7, 8, 23], // Vendor Bills, Expenses, Purchase Orders, Returns
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Parties & Inventory',
    icon: Icons.inventory_2_outlined,
    childIndices: [9, 10, 11, 12], // Parties, Products, Del. Challans, Inventory Adj.
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Accounting',
    icon: Icons.account_balance_outlined,
    childIndices: [13, 14, 15, 16, 17], // Journal Entry, Payments, Bank Recon., Banking, Chart of Accounts
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Reports & Compliance',
    icon: Icons.assessment_outlined,
    childIndices: [18, 19, 20], // Reports, Statements, E-Way Bills
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Tools',
    icon: Icons.build_outlined,
    childIndices: [21, 22, 25, 24, 26], // Audit Log, Reminders, Backup/Restore, Vyapar Import, Settings
  )),
];

// ─── Shell View ───────────────────────────────────────────────

class ShellView extends StatefulWidget {
  const ShellView({super.key});

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  int _selectedIndex = 0;

  Widget get _currentView => _flatItems[_selectedIndex].view;

  void _openSearch() {
    showSearch(context: context, delegate: GlobalSearchDelegate());
  }

  void _refreshCurrentView() {
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
      _openSearch();
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
      setState(() => _selectedIndex = 0); // Dashboard
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyI) {
      setState(() => _selectedIndex = 1); // Invoices
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyB) {
      setState(() => _selectedIndex = 6); // Bills
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyE) {
      setState(() => _selectedIndex = 7); // Expenses
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyR) {
      setState(() => _selectedIndex = 18); // Reports
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && isShiftPressed && event.logicalKey == LogicalKeyboardKey.keyN) {
      // Ctrl+Shift+N → New Invoice
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const InvoiceFormView()),
      );
      return KeyEventResult.handled;
    }

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyT) {
      // Ctrl+T → Toggle dark mode
      context.read<ThemeProvider>().toggleTheme();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _refreshCurrentView();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AdaptiveLayout(
        mobile: _buildMobileLayout(user),
        desktop: _buildDesktopLayout(user),
      ),
    );
  }

  Widget _buildDesktopLayout(UserResponse? user) {
    final syncManager = context.watch<SyncManager>();
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
                _TopBar(
                  title: _flatItems[_selectedIndex].name,
                  onSearch: _openSearch,
                ),
                if (!syncManager.isOnline || syncManager.pendingCount > 0)
                  _OfflineBanner(syncManager: syncManager),
                Expanded(
                  key: ValueKey('${_selectedIndex}_${context.read<AuthProvider>().activeTenantId ?? ''}'),
                  child: _currentView,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(UserResponse? user) {
    final syncManager = context.watch<SyncManager>();
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
        title: Text(_flatItems[_selectedIndex].name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 20),
            onPressed: _openSearch,
            tooltip: 'Search',
          ),
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
      body: Column(
        children: [
          if (!syncManager.isOnline || syncManager.pendingCount > 0)
            _OfflineBanner(syncManager: syncManager),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey('${_selectedIndex}_${context.read<AuthProvider>().activeTenantId ?? ''}'),
                    child: _currentView,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _GroupedNav extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isMobile;

  const _GroupedNav({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isMobile,
  });

  @override
  State<_GroupedNav> createState() => _GroupedNavState();
}

class _GroupedNavState extends State<_GroupedNav> {
  final Set<int> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _autoExpandContainingGroup();
  }

  @override
  void didUpdateWidget(covariant _GroupedNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _autoExpandContainingGroup();
    }
  }

  void _autoExpandContainingGroup() {
    for (var entry in _sidebarEntries) {
      if (entry is _MenuGroupEntry) {
        final gIdx = _sidebarEntries.indexOf(entry);
        if (entry.group.childIndices.contains(widget.selectedIndex)) {
          _expandedGroups.add(gIdx);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padH = widget.isMobile ? 8.0 : 10.0;
    final itemPadV = widget.isMobile ? 12.0 : 10.0;
    final iconSize = widget.isMobile ? 20.0 : 18.0;
    final fontSize = widget.isMobile ? 14.0 : 13.0;
    final childPadH = widget.isMobile ? 14.0 : 16.0;

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: padH),
      itemCount: _sidebarEntries.length,
      itemBuilder: (context, i) {
        final entry = _sidebarEntries[i];

        if (entry is _MenuLeaf) {
          final item = _flatItems[entry.index];
          final isSelected = widget.selectedIndex == entry.index;
          return _buildLeafItem(
            item: item,
            isSelected: isSelected,
            onTap: () => widget.onItemSelected(entry.index),
            itemPadV: itemPadV,
            iconSize: iconSize,
            fontSize: fontSize,
          );
        }

        if (entry is _MenuGroupEntry) {
          final group = entry.group;
          final isExpanded = _expandedGroups.contains(i);
          final hasActiveChild = group.childIndices.contains(widget.selectedIndex);

          return _buildGroupItem(
            group: group,
            isExpanded: isExpanded,
            hasActiveChild: hasActiveChild,
            onToggle: () => setState(() {
              if (_expandedGroups.contains(i)) {
                _expandedGroups.remove(i);
              } else {
                _expandedGroups.add(i);
              }
            }),
            itemPadV: itemPadV,
            iconSize: iconSize,
            fontSize: fontSize,
            childPadH: childPadH,
            selectedIndex: widget.selectedIndex,
            onItemSelected: widget.onItemSelected,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildLeafItem({
    required _MenuItem item,
    required bool isSelected,
    required VoidCallback onTap,
    required double itemPadV,
    required double iconSize,
    required double fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.sidebar,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: itemPadV),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.goldAccent : Colors.transparent,
              borderRadius: AppRadius.sidebar,
            ),
            child: Row(
              children: [
                Icon(item.icon, size: iconSize, color: isSelected ? AppColors.brandNavy : AppColors.textWhiteMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      color: isSelected ? AppColors.brandNavy : Colors.white,
                      fontSize: fontSize,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupItem({
    required _MenuGroupDef group,
    required bool isExpanded,
    required bool hasActiveChild,
    required VoidCallback onToggle,
    required double itemPadV,
    required double iconSize,
    required double fontSize,
    required double childPadH,
    required int selectedIndex,
    required ValueChanged<int> onItemSelected,
  }) {
    final groupTextColor = hasActiveChild ? AppColors.goldAccent : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: AppRadius.sidebar,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: itemPadV - 2),
                child: Row(
                  children: [
                    Icon(group.icon, size: iconSize, color: groupTextColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        group.label,
                        style: TextStyle(
                          color: groupTextColor,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppColors.textWhiteMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.only(left: childPadH),
              child: Column(
                children: group.childIndices.map((childIdx) {
                  final childItem = _flatItems[childIdx];
                  final isSelected = selectedIndex == childIdx;
                  return _buildLeafItem(
                    item: childItem,
                    isSelected: isSelected,
                    onTap: () => onItemSelected(childIdx),
                    itemPadV: itemPadV - 2,
                    iconSize: iconSize - 2,
                    fontSize: fontSize - 1,
                  );
                }).toList(),
              ),
            ),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ─── Desktop Sidebar ──────────────────────────────────────────
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
    final authProvider = context.watch<AuthProvider>();
    final memberships = authProvider.memberships;
    final activeTenantId = authProvider.activeTenantId;

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
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
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
            child: _GroupedNav(
              selectedIndex: selectedIndex,
              onItemSelected: onItemSelected,
              isMobile: false,
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
                // Company Switcher
                if (memberships.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: AppColors.bgSidebar,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          builder: (ctx) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: const BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.white12)),
                                    ),
                                    child: const Text(
                                      'Switch Company',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  ...memberships.map((m) => ListTile(
                                    leading: Icon(
                                      m.tenantId == activeTenantId ? Icons.check_circle : Icons.circle_outlined,
                                      color: m.tenantId == activeTenantId ? AppColors.goldAccent : Colors.white54,
                                    ),
                                    title: Text(
                                      m.tenantName ?? 'Company',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    subtitle: Text(
                                      m.role.toUpperCase(),
                                      style: const TextStyle(color: AppColors.textWhiteMuted, fontSize: 11),
                                    ),
                                    onTap: () {
                                      authProvider.switchTenant(m.tenantId);
                                      Navigator.pop(ctx);
                                    },
                                  )),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      borderRadius: AppRadius.sidebar,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.sidebar,
                          border: Border.all(color: Colors.white12),
                          color: Colors.white.withOpacity(0.05),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.business, size: 16, color: AppColors.textWhiteMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                memberships.firstWhere((m) => m.tenantId == activeTenantId, orElse: () => memberships.first).tenantName ?? 'Company',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.expand_more, size: 16, color: AppColors.textWhiteMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
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

// ─── Top Bar ──────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onSearch;

  const _TopBar({required this.title, this.onSearch});

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
          if (onSearch != null)
            IconButton(
              icon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
              onPressed: onSearch,
              tooltip: 'Search (Ctrl+F)',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              'FY ${DateTime.now().month >= 4 ? '${DateTime.now().year}-${(DateTime.now().year + 1).toString().substring(2)}' : '${(DateTime.now().year - 1)}-${DateTime.now().year.toString().substring(2)}'}',
              style: const TextStyle(
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

// ─── Mobile Drawer ────────────────────────────────────────────
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
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
          child: _GroupedNav(
            selectedIndex: selectedIndex,
            onItemSelected: onItemSelected,
            isMobile: true,
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
                  // Company Switcher
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      final memberships = auth.memberships;
                      final activeTenantId = auth.activeTenantId;
                      if (memberships.length <= 1) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: AppColors.bgSidebar,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              builder: (ctx) {
                                return SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white12)),
                                        ),
                                        child: const Text(
                                          'Switch Company',
                                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      ...memberships.map((m) => ListTile(
                                        leading: Icon(
                                          m.tenantId == activeTenantId ? Icons.check_circle : Icons.circle_outlined,
                                          color: m.tenantId == activeTenantId ? AppColors.goldAccent : Colors.white54,
                                        ),
                                        title: Text(
                                          m.tenantName ?? 'Company',
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                        subtitle: Text(
                                          m.role.toUpperCase(),
                                          style: const TextStyle(color: AppColors.textWhiteMuted, fontSize: 11),
                                        ),
                                        onTap: () {
                                          auth.switchTenant(m.tenantId);
                                          Navigator.pop(ctx);
                                          Navigator.pop(context); // Close drawer
                                        },
                                      )),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                              color: Colors.white.withOpacity(0.05),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.business, size: 16, color: AppColors.textWhiteMuted),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    memberships.firstWhere((m) => m.tenantId == activeTenantId, orElse: () => memberships.first).tenantName ?? 'Company',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.expand_more, size: 16, color: AppColors.textWhiteMuted),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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
