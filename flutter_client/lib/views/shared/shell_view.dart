import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/providers/theme_provider.dart';
import 'package:flutter_client/core/sync_manager.dart';
import 'package:flutter_client/models/auth.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/global_search.dart';
import 'package:flutter_client/views/dashboard/sales_dashboard_view.dart';
import 'package:flutter_client/views/invoices/invoice_list_view.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/products/product_list_view.dart';
import 'package:flutter_client/views/contacts/contact_list_view.dart';
import 'package:flutter_client/views/estimates/estimate_list_view.dart';
import 'package:flutter_client/views/expenses/expense_list_view.dart';
import 'package:flutter_client/views/bills/bill_list_view.dart';
import 'package:flutter_client/views/credit_notes/credit_note_list_view.dart';
import 'package:flutter_client/views/purchase_orders/order_list_view.dart';
import 'package:flutter_client/views/accounting/journal_entry_view.dart';
import 'package:flutter_client/views/accounting/statement_view.dart';
import 'package:flutter_client/views/accounting/year_end_view.dart';
import 'package:flutter_client/views/financial_years/financial_years_manage_view.dart';
import 'package:flutter_client/views/payments/payment_list_view.dart';
import 'package:flutter_client/views/accounting/account_list_view.dart';
import 'package:flutter_client/views/einvoice/eway_bill_list_view.dart';
import 'package:flutter_client/views/reports/report_list_view.dart';
import 'package:flutter_client/views/settings/settings_view.dart';
import 'package:flutter_client/providers/settings_provider.dart';
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
import 'package:flutter_client/views/tally/tally_import_view.dart';
import 'package:flutter_client/views/shared/goto_dialog.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';

// ─── Financial Year Picker Helper (Sidebar/Mobile) ──────────

void _showFYSidebarPicker(BuildContext context, FinancialYearProvider provider) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgSidebar,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
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
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.goldAccent),
                  const SizedBox(width: 8),
                  const Text(
                    'Financial Years',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: provider.availableYears.length,
                itemBuilder: (context, i) {
                  final year = provider.availableYears[i];
                  final isActive = provider.activeYear?.id == year.id;
                  final statusColor = year.status.color;
                  final statusBg = year.status.bgColor;

                  return Container(
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.goldAccent.withValues(alpha: 0.1) : null,
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.goldAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            'FY ${year.name}',
                            style: TextStyle(
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          if (year.status == FYStatus.current) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: FYStatus.current.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'CURRENT',
                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: FYStatus.current.color),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            year.dateRange,
                            style: const TextStyle(fontSize: 11, color: AppColors.textWhiteMuted),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              year.status.label.toUpperCase(),
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                      trailing: isActive
                          ? const Icon(Icons.check_circle, size: 18, color: AppColors.goldAccent)
                          : null,
                      onTap: () {
                        provider.setActiveYear(year);
                        Navigator.pop(ctx);
                      },
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FinancialYearsManageView()),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined, size: 14),
                      label: const Text('Manage Financial Years'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

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

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: bgColor,
        child: Row(
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600),
              ),
            ),
            if (pending > 0) ...[
              TextButton(
                onPressed: () => syncManager.syncPendingActions(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'RETRY SYNC',
                  style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (!isOffline && pending > 0)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
              ),
          ],
        ),
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
  _MenuItem(name: 'Tally Import/Export', icon: Icons.swap_horiz_rounded, view: const TallyImportView()),
  _MenuItem(name: 'Backup/Restore', icon: Icons.backup_rounded, view: const BackupRestoreView()),
  _MenuItem(name: 'Settings', icon: Icons.settings_rounded, view: const SettingsView()),
  _MenuItem(name: 'Year End Close', icon: Icons.lock_clock_outlined, view: const YearEndCloseView()),
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
    childIndices: [13, 14, 15, 16, 17, 28], // Journal Entry, Payments, Bank Recon., Banking, Chart of Accounts, Year End Close
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Reports & Compliance',
    icon: Icons.assessment_outlined,
    childIndices: [18, 19, 20], // Reports, Statements, E-Way Bills
  )),
  _MenuGroupEntry(_MenuGroupDef(
    label: 'Tools',
    icon: Icons.build_outlined,
    childIndices: [21, 22, 26, 24, 25, 27], // Audit Log, Reminders, Backup/Restore, Vyapar Import, Tally Import, Settings
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int get _mobileBottomNavIndex {
    switch (_selectedIndex) {
      case 0: return 0;
      case 1: return 1;
      case 9: return 2;
      case 18: return 3;
      default: return 4;
    }
  }

  void _onMobileBottomNavTap(int index) {
    if (index == 4) {
      _scaffoldKey.currentState?.openDrawer();
    } else {
      int targetIndex = 0;
      switch (index) {
        case 0: targetIndex = 0; break;
        case 1: targetIndex = 1; break;
        case 2: targetIndex = 9; break;
        case 3: targetIndex = 18; break;
      }
      setState(() {
        _selectedIndex = targetIndex;
      });
    }
  }

  Widget get _currentView => _flatItems[_selectedIndex].view;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    super.dispose();
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;

    if ((isCtrlPressed || isAltPressed) && event.logicalKey == LogicalKeyboardKey.keyG) {
      _openGoTo();
      return true;
    }
    return false;
  }

  void _openGoTo() {
    GoToDialog.show(
      context,
      isInShell: true,
      onSelectTab: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  void _openSearch() {
    showSearch(context: context, delegate: GlobalSearchDelegate());
  }

  String _activeFYLabel(BuildContext context) {
    final fy = context.read<FinancialYearProvider>().activeYear;
    return fy?.label ?? '';
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
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if ((isCtrlPressed || isAltPressed) && event.logicalKey == LogicalKeyboardKey.keyG) {
      _openGoTo();
      return KeyEventResult.handled;
    }

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
                  onGoTo: _openGoTo,
                ),
                if (!syncManager.isOnline || syncManager.pendingCount > 0)
                  _OfflineBanner(syncManager: syncManager),
                const _HistoricalYearBanner(),
                Expanded(
                  key: ValueKey('${_selectedIndex}_${context.read<AuthProvider>().activeTenantId ?? ''}_${_activeFYLabel(context)}'),
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
      key: _scaffoldKey,
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
            icon: const Icon(Icons.explore_outlined, size: 20),
            onPressed: _openGoTo,
            tooltip: 'Go To (Alt+G)',
          ),
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
          const _HistoricalYearBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey('${_selectedIndex}_${context.read<AuthProvider>().activeTenantId ?? ''}_${_activeFYLabel(context)}'),
                child: _currentView,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: AppSpeedDial(
        options: [
          AppSpeedDialOption(
            icon: Icons.receipt_long_outlined,
            label: 'New Invoice',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InvoiceFormView()),
              );
            },
          ),
          AppSpeedDialOption(
            icon: Icons.money_off_rounded,
            label: 'New Expense',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpenseFormView()),
              );
            },
          ),
          AppSpeedDialOption(
            icon: Icons.payments_rounded,
            label: 'New Payment',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => PaymentFormView(mode: 'receipt', onSuccess: () => Navigator.pop(ctx))),
              );
            },
          ),
          AppSpeedDialOption(
            icon: Icons.receipt_rounded,
            label: 'New Bill',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BillFormView()),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        color: AppColors.bgSurface,
        child: BottomNavigationBar(
          currentIndex: _mobileBottomNavIndex,
          onTap: _onMobileBottomNavTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Sales',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_rounded),
              label: 'Parties',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Reports',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_rounded),
              label: 'More',
            ),
          ],
        ),
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
    final padH = widget.isMobile ? 8.0 : 9.0;
    final itemPadV = widget.isMobile ? 11.0 : 9.0;
    final iconSize = widget.isMobile ? 20.0 : 18.0;
    final fontSize = widget.isMobile ? 14.0 : 13.0;
    final childPadH = widget.isMobile ? 14.0 : 14.0;

    bool gstEnabled = true;
    try {
      gstEnabled = context.watch<SettingsProvider>().gstEnabled;
    } catch (_) {}
    final hiddenNames = {'E-Way Bills'};

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: padH),
      itemCount: _sidebarEntries.length,
      itemBuilder: (context, i) {
        final entry = _sidebarEntries[i];

        if (entry is _MenuLeaf) {
          final item = _flatItems[entry.index];
          if (!gstEnabled && hiddenNames.contains(item.name)) {
            return const SizedBox.shrink();
          }
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
          final visibleChildren = gstEnabled
              ? group.childIndices
              : group.childIndices.where((idx) => !hiddenNames.contains(_flatItems[idx].name)).toList();
          if (visibleChildren.isEmpty) return const SizedBox.shrink();
          final isExpanded = _expandedGroups.contains(i);
          final hasActiveChild = visibleChildren.contains(widget.selectedIndex);

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
            visibleChildIndices: gstEnabled ? null : visibleChildren,
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
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.sidebar,
          hoverColor: Colors.white.withOpacity(0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: itemPadV),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.goldAccent.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: AppRadius.sidebar,
            ),
            child: Row(
              children: [
                Icon(item.icon, size: iconSize, color: isSelected ? AppColors.goldAccent : AppColors.textWhiteMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      color: isSelected ? AppColors.goldAccent : Colors.white,
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
    List<int>? visibleChildIndices,
  }) {
    final childIndices = visibleChildIndices ?? group.childIndices;
    final groupTextColor = hasActiveChild ? AppColors.goldAccent : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: AppRadius.sidebar,
              hoverColor: Colors.white.withOpacity(0.04),
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
                children: childIndices.map((childIdx) {
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
    final currentMembership = memberships.isNotEmpty
        ? memberships.firstWhere(
            (m) => m.tenantId == activeTenantId,
            orElse: () => memberships.first,
          )
        : null;
    final companyName = currentMembership?.tenantName ?? 'Apex Books';

    return Container(
      width: AdaptiveLayout.sidebarWidth,
      color: AppColors.bgSidebar,
      child: Column(
        children: [
          // Brand Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                AppAvatar(name: companyName, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companyName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
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
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

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
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white12)),
              color: AppColors.brandNavyDark,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Financial Year Selector
                Consumer<FinancialYearProvider>(
                  builder: (context, fy, _) {
                    if (fy.activeYear == null) return const SizedBox.shrink();
                    final year = fy.activeYear!;
                    final isLocked = year.status == FYStatus.locked;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => _showFYSidebarPicker(context, fy),
                        borderRadius: AppRadius.sidebar,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.sidebar,
                            border: Border.all(color: Colors.white12),
                            color: isLocked
                                ? AppColors.error.withValues(alpha: 0.1)
                                : fy.isViewingHistoricalYear
                                    ? AppColors.warning.withValues(alpha: 0.15)
                                    : Colors.white.withOpacity(0.05),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isLocked ? Icons.lock_outline : Icons.calendar_today_outlined,
                                size: 14,
                                color: isLocked
                                    ? AppColors.error
                                    : fy.isViewingHistoricalYear
                                        ? AppColors.warning
                                        : AppColors.textWhiteMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'FY ${year.name}',
                                      style: TextStyle(
                                        color: isLocked
                                            ? AppColors.error
                                            : fy.isViewingHistoricalYear
                                                ? AppColors.warning
                                                : Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      year.status.label,
                                      style: TextStyle(
                                        color: year.status.color.withValues(alpha: 0.8),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.expand_more, size: 16, color: AppColors.textWhiteMuted),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
                                memberships.isNotEmpty
                                    ? memberships.firstWhere(
                                        (m) => m.tenantId == activeTenantId,
                                        orElse: () => memberships.first,
                                      ).tenantName ??
                                        'Company'
                                    : 'Company',
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
                const SizedBox(height: 10),
                InkWell(
                  onTap: onLogout,
                  borderRadius: AppRadius.sidebar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
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

// ─── Financial Year Selector ─────────────────────────────────
class _FYSelector extends StatelessWidget {
  const _FYSelector();

  @override
  Widget build(BuildContext context) {
    return Consumer<FinancialYearProvider>(
      builder: (context, fy, _) {
        if (fy.activeYear == null) return const SizedBox.shrink();

        final year = fy.activeYear!;
        final statusColor = year.status.color;
        final statusBg = year.status.bgColor;
        final isHistorical = fy.isViewingHistoricalYear;

        return InkWell(
          onTap: () => _showModernFYDropdown(context, fy),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isHistorical
                  ? AppColors.warning.withValues(alpha: 0.1)
                  : AppColors.borderLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: isHistorical
                  ? Border.all(color: AppColors.warning.withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: isHistorical ? AppColors.warning : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'FY ${year.label}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isHistorical ? AppColors.warning : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    year.status.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  size: 14,
                  color: isHistorical ? AppColors.warning : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showModernFYDropdown(BuildContext context, FinancialYearProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.brandNavy),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Financial Years',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: provider.availableYears.length,
                  itemBuilder: (context, i) {
                    final year = provider.availableYears[i];
                    final isActive = provider.activeYear?.id == year.id;
                    final statusColor = year.status.color;
                    final statusBg = year.status.bgColor;

                    return Container(
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.brandNavy.withValues(alpha: 0.04) : null,
                        border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 4,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.brandNavy : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              'FY ${year.name}',
                              style: TextStyle(
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            if (year.status == FYStatus.current) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: FYStatus.current.bgColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'CURRENT',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: FYStatus.current.color,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Text(
                                year.dateRange,
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  year.status.label.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              if (year.transactionCount > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${year.transactionCount} txn${year.transactionCount == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        trailing: isActive
                            ? const Icon(Icons.check_circle, size: 18, color: AppColors.brandNavy)
                            : null,
                        onTap: () {
                          provider.setActiveYear(year);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FinancialYearsManageView(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined, size: 14),
                        label: const Text('Manage Financial Years'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandNavy,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Historical Year Banner (enhanced) ──────────────────────
class _HistoricalYearBanner extends StatelessWidget {
  const _HistoricalYearBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<FinancialYearProvider>(
      builder: (context, fy, _) {
        if (fy.activeYear == null) return const SizedBox.shrink();
        final year = fy.activeYear!;

        if (year.status == FYStatus.locked) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.error.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'FY ${year.name} is ${year.status.label.toLowerCase()} and locked. No transactions can be modified.',
                    style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final currentFY = fy.availableYears.firstWhere(
                      (y) => y.isCurrent,
                      orElse: () => fy.availableYears.first,
                    );
                    fy.setActiveYear(currentFY);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Switch to Current FY'),
                ),
              ],
            ),
          );
        }

        if (fy.isViewingHistoricalYear) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.warning.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.lock_clock_outlined, size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Viewing ${year.fullLabel} — read-only mode',
                    style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final currentFY = fy.availableYears.firstWhere(
                      (y) => y.isCurrent,
                      orElse: () => fy.availableYears.first,
                    );
                    fy.setActiveYear(currentFY);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Switch to Current FY'),
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onSearch;
  final VoidCallback? onGoTo;

  const _TopBar({required this.title, this.onSearch, this.onGoTo});

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
          if (onGoTo != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: onGoTo,
                icon: const Icon(Icons.explore_outlined, size: 16),
                label: const Text('Go To (Alt+G)'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandNavy,
                  backgroundColor: AppColors.borderLight,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
          if (onSearch != null)
            IconButton(
              icon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
              onPressed: onSearch,
              tooltip: 'Search (Ctrl+F)',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          const _FYSelector(),
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
                  // Financial Year Selector
                  Consumer<FinancialYearProvider>(
                    builder: (context, fy, _) {
                      if (fy.activeYear == null) return const SizedBox.shrink();
                      final year = fy.activeYear!;
                      final isLocked = year.status == FYStatus.locked;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(context); // Close drawer first
                            _showFYSidebarPicker(context, fy);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                              color: isLocked
                                  ? AppColors.error.withValues(alpha: 0.1)
                                  : fy.isViewingHistoricalYear
                                      ? AppColors.warning.withValues(alpha: 0.15)
                                      : Colors.white.withOpacity(0.05),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isLocked ? Icons.lock_outline : Icons.calendar_today_outlined,
                                  size: 16,
                                  color: isLocked
                                      ? AppColors.error
                                      : fy.isViewingHistoricalYear
                                          ? AppColors.warning
                                          : AppColors.textWhiteMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'FY ${year.name}',
                                        style: TextStyle(
                                          color: isLocked
                                              ? AppColors.error
                                              : fy.isViewingHistoricalYear
                                                  ? AppColors.warning
                                                  : Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        year.status.label,
                                        style: TextStyle(
                                          color: year.status.color.withValues(alpha: 0.8),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.expand_more, size: 16, color: AppColors.textWhiteMuted),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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
                                    memberships.isNotEmpty
                                        ? memberships.firstWhere(
                                            (m) => m.tenantId == activeTenantId,
                                            orElse: () => memberships.first,
                                          ).tenantName ??
                                            'Company'
                                        : 'Company',
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
