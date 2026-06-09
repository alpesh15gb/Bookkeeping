import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/core/constants.dart';

// Import all creation form views
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/estimates/estimate_form_view.dart';
import 'package:flutter_client/views/purchase_orders/purchase_order_form_view.dart';
import 'package:flutter_client/views/credit_notes/credit_debit_note_form_view.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_form_view.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_form_view.dart';
import 'package:flutter_client/views/accounting/journal_entry_form_view.dart';
import 'package:flutter_client/views/accounting/account_form_view.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/products/product_form_view.dart';

// Import list / report views
import 'package:flutter_client/views/invoices/invoice_list_view.dart';
import 'package:flutter_client/views/bills/bill_list_view.dart';
import 'package:flutter_client/views/payments/payment_list_view.dart';
import 'package:flutter_client/views/expenses/expense_list_view.dart';
import 'package:flutter_client/views/estimates/estimate_list_view.dart';
import 'package:flutter_client/views/credit_notes/credit_note_list_view.dart';
import 'package:flutter_client/views/purchase_orders/order_list_view.dart';
import 'package:flutter_client/views/contacts/contact_list_view.dart';
import 'package:flutter_client/views/products/product_list_view.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_list_view.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_list_view.dart';
import 'package:flutter_client/views/accounting/journal_entry_view.dart';
import 'package:flutter_client/views/bank_reconciliation/bank_reconciliation_list_view.dart';
import 'package:flutter_client/views/banking/banking_profile_list_view.dart';
import 'package:flutter_client/views/accounting/account_list_view.dart';
import 'package:flutter_client/views/reports/report_list_view.dart';
import 'package:flutter_client/views/accounting/statement_view.dart';
import 'package:flutter_client/views/einvoice/eway_bill_list_view.dart';
import 'package:flutter_client/views/audit/audit_log_list_view.dart';
import 'package:flutter_client/views/reminders/reminder_list_view.dart';
import 'package:flutter_client/views/returns/returns_list_view.dart';
import 'package:flutter_client/views/settings/settings_view.dart';
import 'package:flutter_client/views/sales_analytics/sales_analytics_view.dart';
import 'package:flutter_client/views/reports/cash_book_view.dart';
import 'package:flutter_client/views/accounting/year_end_view.dart';
import 'package:flutter_client/views/financial_years/financial_years_manage_view.dart';

class GoToItem {
  final String name;
  final String category;
  final IconData icon;
  final Widget Function(BuildContext) builder;
  final int? shellTabIndex; // If on shell and can just switch tab

  const GoToItem({
    required this.name,
    required this.category,
    required this.icon,
    required this.builder,
    this.shellTabIndex,
  });
}

class GoToDialog extends StatefulWidget {
  final ValueChanged<int>? onSelectTab;
  final bool isInShell;

  static final List<String> _recentItemNames = [];

  const GoToDialog({
    super.key,
    this.onSelectTab,
    this.isInShell = false,
  });

  static void show(BuildContext context, {ValueChanged<int>? onSelectTab, bool isInShell = false}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'GoTo Dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, __) {
        return GoToDialog(
          onSelectTab: onSelectTab,
          isInShell: isInShell,
        );
      },
    );
  }

  @override
  State<GoToDialog> createState() => _GoToDialogState();
}

class _GoToDialogState extends State<GoToDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _selectedIndex = 0;

  late final List<GoToItem> _allItems;
  List<GoToItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _initItems();
    _filterItems('');
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _initItems() {
    _allItems = [
      // 1. Voucher Creation (Forms)
      GoToItem(
        name: 'Create Invoice (Sales)',
        category: 'Voucher Creation',
        icon: Icons.add_chart_rounded,
        builder: (_) => const InvoiceFormView(),
      ),
      GoToItem(
        name: 'Create Vendor Bill (Purchase)',
        category: 'Voucher Creation',
        icon: Icons.add_home_work_rounded,
        builder: (_) => const BillFormView(),
      ),
      GoToItem(
        name: 'Create Payment Receipt',
        category: 'Voucher Creation',
        icon: Icons.add_card_rounded,
        builder: (_) => PaymentFormView(mode: 'receipt', onSuccess: () {}),
      ),
      GoToItem(
        name: 'Create Expense Voucher',
        category: 'Voucher Creation',
        icon: Icons.money_off_rounded,
        builder: (_) => const ExpenseFormView(),
      ),
      GoToItem(
        name: 'Create Quotation / Estimate',
        category: 'Voucher Creation',
        icon: Icons.request_quote_rounded,
        builder: (_) => const EstimateFormView(),
      ),
      GoToItem(
        name: 'Create Sales Order',
        category: 'Voucher Creation',
        icon: Icons.receipt_long_outlined,
        builder: (_) => const PurchaseOrderFormView(orderType: 'sales'),
      ),
      GoToItem(
        name: 'Create Purchase Order',
        category: 'Voucher Creation',
        icon: Icons.shopping_cart_outlined,
        builder: (_) => const PurchaseOrderFormView(orderType: 'purchase'),
      ),
      GoToItem(
        name: 'Create Credit Note',
        category: 'Voucher Creation',
        icon: Icons.compare_arrows_rounded,
        builder: (_) => const CreditDebitNoteFormView(isCredit: true),
      ),
      GoToItem(
        name: 'Create Debit Note',
        category: 'Voucher Creation',
        icon: Icons.compare_arrows_rounded,
        builder: (_) => const CreditDebitNoteFormView(isCredit: false),
      ),
      GoToItem(
        name: 'Create Delivery Challan',
        category: 'Voucher Creation',
        icon: Icons.local_shipping_rounded,
        builder: (_) => const DeliveryChallanFormView(),
      ),
      GoToItem(
        name: 'Create Inventory Adjustment',
        category: 'Voucher Creation',
        icon: Icons.tune_rounded,
        builder: (_) => const InventoryAdjustmentFormView(),
      ),
      GoToItem(
        name: 'Create Journal Entry',
        category: 'Voucher Creation',
        icon: Icons.book_rounded,
        builder: (_) => const JournalEntryFormView(),
      ),
      GoToItem(
        name: 'Create Ledger Account',
        category: 'Voucher Creation',
        icon: Icons.account_balance_rounded,
        builder: (_) => AccountFormView(onSuccess: () {}),
      ),
      GoToItem(
        name: 'Create Party (Customer/Vendor)',
        category: 'Voucher Creation',
        icon: Icons.person_add_rounded,
        builder: (_) => const ContactFormView(),
      ),
      GoToItem(
        name: 'Create Product Item',
        category: 'Voucher Creation',
        icon: Icons.add_box_rounded,
        builder: (_) => const ProductFormView(),
      ),

      // 2. Reports & Analytics
      GoToItem(
        name: 'Financial Statements (Profit & Loss, Balance Sheet)',
        category: 'Reports & Analytics',
        icon: Icons.assessment_rounded,
        shellTabIndex: 19,
        builder: (_) => const StatementView(),
      ),
      GoToItem(
        name: 'All Reports List',
        category: 'Reports & Analytics',
        icon: Icons.bar_chart_rounded,
        shellTabIndex: 18,
        builder: (_) => const ReportListView(),
      ),
      GoToItem(
        name: 'Sales Analytics Dashboard',
        category: 'Reports & Analytics',
        icon: Icons.analytics_rounded,
        shellTabIndex: 5,
        builder: (_) => const SalesAnalyticsView(),
      ),
      GoToItem(
        name: 'Cash Book Report',
        category: 'Reports & Analytics',
        icon: Icons.book_online_outlined,
        shellTabIndex: 29,
        builder: (_) => const CashBookView(),
      ),
      GoToItem(
        name: 'Audit Logs Logbook',
        category: 'Reports & Analytics',
        icon: Icons.history_rounded,
        shellTabIndex: 21,
        builder: (_) => const AuditLogListView(),
      ),
      GoToItem(
        name: 'Reminders & Notifications',
        category: 'Reports & Analytics',
        icon: Icons.notifications_outlined,
        shellTabIndex: 22,
        builder: (_) => const ReminderListView(),
      ),

      // 3. Masters & Lists
      GoToItem(
        name: 'Invoices Register',
        category: 'Masters & Lists',
        icon: Icons.description_rounded,
        shellTabIndex: 1,
        builder: (_) => const InvoiceListView(),
      ),
      GoToItem(
        name: 'Vendor Bills Register',
        category: 'Masters & Lists',
        icon: Icons.receipt_rounded,
        shellTabIndex: 6,
        builder: (_) => const BillListView(),
      ),
      GoToItem(
        name: 'Estimates List',
        category: 'Masters & Lists',
        icon: Icons.request_quote_rounded,
        shellTabIndex: 2,
        builder: (_) => const EstimateListView(),
      ),
      GoToItem(
        name: 'Sales Orders List',
        category: 'Masters & Lists',
        icon: Icons.receipt_long_outlined,
        shellTabIndex: 3,
        builder: (_) => const OrderListView(orderType: 'sales'),
      ),
      GoToItem(
        name: 'Purchase Orders List',
        category: 'Masters & Lists',
        icon: Icons.shopping_cart_outlined,
        shellTabIndex: 8,
        builder: (_) => const OrderListView(orderType: 'purchase'),
      ),
      GoToItem(
        name: 'Credit & Debit Notes List',
        category: 'Masters & Lists',
        icon: Icons.compare_arrows_rounded,
        shellTabIndex: 4,
        builder: (_) => CreditNoteListView(),
      ),
      GoToItem(
        name: 'Payments List',
        category: 'Masters & Lists',
        icon: Icons.payments_rounded,
        shellTabIndex: 14,
        builder: (_) => const PaymentListView(),
      ),
      GoToItem(
        name: 'Expenses List',
        category: 'Masters & Lists',
        icon: Icons.money_off_rounded,
        shellTabIndex: 7,
        builder: (_) => const ExpenseListView(),
      ),
      GoToItem(
        name: 'Parties / Contacts Directory',
        category: 'Masters & Lists',
        icon: Icons.people_rounded,
        shellTabIndex: 9,
        builder: (_) => const ContactListView(),
      ),
      GoToItem(
        name: 'Products & Inventory items',
        category: 'Masters & Lists',
        icon: Icons.inventory_2_rounded,
        shellTabIndex: 10,
        builder: (_) => const ProductListView(),
      ),
      GoToItem(
        name: 'Delivery Challans Register',
        category: 'Masters & Lists',
        icon: Icons.local_shipping_rounded,
        shellTabIndex: 11,
        builder: (_) => const DeliveryChallanListView(),
      ),
      GoToItem(
        name: 'Inventory Adjustments History',
        category: 'Masters & Lists',
        icon: Icons.tune_rounded,
        shellTabIndex: 12,
        builder: (_) => const InventoryAdjustmentListView(),
      ),
      GoToItem(
        name: 'Journal Entries Register',
        category: 'Masters & Lists',
        icon: Icons.book_rounded,
        shellTabIndex: 13,
        builder: (_) => const JournalEntryView(),
      ),
      GoToItem(
        name: 'Bank Reconciliation Register',
        category: 'Masters & Lists',
        icon: Icons.account_balance_outlined,
        shellTabIndex: 15,
        builder: (_) => const BankReconciliationListView(),
      ),
      GoToItem(
        name: 'Banking Profiles',
        category: 'Masters & Lists',
        icon: Icons.account_balance_wallet_outlined,
        shellTabIndex: 16,
        builder: (_) => const BankingProfileListView(),
      ),
      GoToItem(
        name: 'Chart of Accounts Ledger',
        category: 'Masters & Lists',
        icon: Icons.account_balance_rounded,
        shellTabIndex: 17,
        builder: (_) => const AccountListView(),
      ),
      GoToItem(
        name: 'E-Way Bills Registry',
        category: 'Masters & Lists',
        icon: Icons.local_shipping_outlined,
        shellTabIndex: 20,
        builder: (_) => const EwayBillListView(),
      ),
      GoToItem(
        name: 'Sales & Purchase Returns',
        category: 'Masters & Lists',
        icon: Icons.assignment_return_rounded,
        shellTabIndex: 23,
        builder: (_) => const ReturnsListView(),
      ),
      GoToItem(
        name: 'System Settings',
        category: 'Masters & Lists',
        icon: Icons.settings_rounded,
        shellTabIndex: 27,
        builder: (_) => const SettingsView(),
      ),
      GoToItem(
        name: 'Year End Lock/Close',
        category: 'Masters & Lists',
        icon: Icons.lock_clock_outlined,
        shellTabIndex: 28,
        builder: (_) => const YearEndCloseView(),
      ),
      GoToItem(
        name: 'Financial Years',
        category: 'Masters & Lists',
        icon: Icons.calendar_month_outlined,
        shellTabIndex: 28,
        builder: (_) => const FinancialYearsManageView(),
      ),
    ];
  }

  void _filterItems(String query) {
    setState(() {
      final recents = <GoToItem>[];
      for (final name in GoToDialog._recentItemNames) {
        final matches = _allItems.where((item) => item.name == name);
        if (matches.isNotEmpty) {
          final match = matches.first;
          recents.add(GoToItem(
            name: match.name,
            category: 'Show Opened / Recent',
            icon: match.icon,
            builder: match.builder,
            shellTabIndex: match.shellTabIndex,
          ));
        }
      }

      if (query.isEmpty) {
        _filteredItems = recents + List.from(_allItems);
      } else {
        final lowercaseQuery = query.toLowerCase();
        final filteredRecents = recents.where((item) => item.name.toLowerCase().contains(lowercaseQuery)).toList();
        final filteredAll = _allItems.where((item) {
          return item.name.toLowerCase().contains(lowercaseQuery) ||
              item.category.toLowerCase().contains(lowercaseQuery);
        }).toList();
        _filteredItems = filteredRecents + filteredAll;
      }
      _selectedIndex = 0;
    });
  }

  void _navigateToGoToItem(GoToItem item) {
    // Record in recents (Tally Prime "View opened reports" tracking)
    GoToDialog._recentItemNames.remove(item.name);
    GoToDialog._recentItemNames.insert(0, item.name);
    if (GoToDialog._recentItemNames.length > 5) {
      GoToDialog._recentItemNames.removeLast();
    }

    Navigator.pop(context); // Close the GoTo dialog first

    if (widget.isInShell && item.shellTabIndex != null && widget.onSelectTab != null) {
      // Just switch the active tab in shell view in-place
      widget.onSelectTab!(item.shellTabIndex!);
    } else {
      final targetWidget = item.builder(context);
      if (targetWidget is Dialog || targetWidget is AccountFormView || targetWidget is ContactFormView || targetWidget is PaymentFormView || targetWidget is ProductFormView) {
        showDialog(
          context: context,
          builder: (context) => targetWidget is Dialog ? targetWidget : Dialog(child: targetWidget),
        );
      } else {
        // Push the selected view on top of the Navigator stack to preserve current state.
        // Wrap it in a Scaffold with a Back button.
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(item.name.split(' (').first), // Keep short title
                backgroundColor: AppColors.bgSidebar,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              body: targetWidget,
            ),
          ),
        );
      }
    }
  }

  void _handleKeyDown(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_filteredItems.isNotEmpty) {
          _selectedIndex = (_selectedIndex + 1) % _filteredItems.length;
        }
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_filteredItems.isNotEmpty) {
          _selectedIndex = (_selectedIndex - 1 + _filteredItems.length) % _filteredItems.length;
        }
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filteredItems.isNotEmpty) {
        _navigateToGoToItem(_filteredItems[_selectedIndex]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyDown,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 560,
            height: 480,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.dialog,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandNavy,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Go To',
                          style: TextStyle(
                            color: AppColors.goldAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _filterItems,
                          decoration: const InputDecoration(
                            hintText: 'Search reports, vouchers or masters...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Results list
                Expanded(
                  child: _filteredItems.isEmpty
                      ? const Center(
                          child: Text(
                            'No matches found',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            final isSelected = index == _selectedIndex;

                            // Header for categories
                            final showCategoryHeader = index == 0 ||
                                _filteredItems[index - 1].category != item.category;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showCategoryHeader)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                    child: Text(
                                      item.category.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.brandNavy,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () => _navigateToGoToItem(item),
                                  child: Container(
                                    color: isSelected
                                        ? AppColors.brandNavy.withOpacity(0.06)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          item.icon,
                                          size: 18,
                                          color: isSelected
                                              ? AppColors.brandNavy
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: isSelected
                                                  ? AppColors.brandNavy
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Text(
                                            '⏎ Enter',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.brandNavy,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                const Divider(),
                // Footer
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Use Alt+G or Ctrl+G to open anywhere',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      Row(
                        children: const [
                          Icon(Icons.arrow_upward, size: 12, color: AppColors.textMuted),
                          Icon(Icons.arrow_downward, size: 12, color: AppColors.textMuted),
                          SizedBox(width: 4),
                          Text(
                            'Navigate',
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
