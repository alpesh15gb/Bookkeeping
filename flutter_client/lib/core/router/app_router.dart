import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/financial_year_provider.dart';
import '../../views/auth/login_view.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/invoices/invoice_list_screen.dart';
import '../../features/create_invoice/create_invoice_screen.dart';
import '../../features/invoice_detail/invoice_detail_screen.dart';
import '../../features/parties/party_list_screen.dart';
import '../../features/parties/party_detail_screen.dart';
import '../../features/bills/bill_list_screen.dart';
import '../../features/expenses/expense_list_screen.dart';
import '../../features/payments/payment_list_screen.dart';
import '../../features/products/product_list_screen.dart';
import '../../features/banking/banking_screens.dart';
import '../../features/reports/reports_screens.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/others/other_screens.dart';
import '../../features/recurring_invoices/recurring_invoice_screens.dart';
import '../../features/terms_templates/terms_templates_screen.dart';
import 'shell_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',
  redirect: (context, state) {
    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = authProvider.isAuthenticated;
    final isLoading = authProvider.isLoading;
    final path = state.uri.path;

    if (isLoading) return null;

    if (!isLoggedIn && path != '/login') {
      return '/login';
    }

    if (isLoggedIn && path == '/login') {
      return '/dashboard';
    }

    if (isLoggedIn && authProvider.currentUser != null) {
      final fyProvider = context.read<FinancialYearProvider>();
      if (!fyProvider.isLoading && fyProvider.activeYear == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          fyProvider.init();
        });
      }
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginView(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => ShellScreen(child: child),
      routes: [
        GoRoute(path: '/dashboard', name: 'dashboard', builder: (context, state) => const DashboardScreen()),
        GoRoute(path: '/invoices', name: 'invoices', builder: (context, state) => const InvoiceListScreen()),
        GoRoute(path: '/invoices/create', name: 'create-invoice', builder: (context, state) => const CreateInvoiceScreen()),
        GoRoute(path: '/invoices/:id', name: 'invoice-detail', builder: (context, state) => InvoiceDetailScreen(id: state.pathParameters['id']!)),
        GoRoute(path: '/estimates', name: 'estimates', builder: (context, state) => const EstimatesScreen()),
        GoRoute(path: '/sales-orders', name: 'sales-orders', builder: (context, state) => const SalesOrdersScreen()),
        GoRoute(path: '/credit-notes', name: 'credit-notes', builder: (context, state) => const CreditNotesScreen()),
        GoRoute(path: '/bills', name: 'bills', builder: (context, state) => const BillListScreen()),
        GoRoute(path: '/expenses', name: 'expenses', builder: (context, state) => const ExpenseListScreen()),
        GoRoute(path: '/purchase-orders', name: 'purchase-orders', builder: (context, state) => const PurchaseOrdersScreen()),
        GoRoute(path: '/debit-notes', name: 'debit-notes', builder: (context, state) => const DebitNotesScreen()),
        GoRoute(path: '/returns', name: 'returns', builder: (context, state) => const ReturnsScreen()),
        GoRoute(path: '/parties', name: 'parties', builder: (context, state) => const PartyListScreen()),
        GoRoute(path: '/parties/:id', name: 'party-detail', builder: (context, state) => PartyDetailScreen(id: state.pathParameters['id']!)),
        GoRoute(path: '/products', name: 'products', builder: (context, state) => const ProductListScreen()),
        GoRoute(path: '/delivery-challans', name: 'delivery-challans', builder: (context, state) => const DeliveryChallansScreen()),
        GoRoute(path: '/inventory-adjustments', name: 'inventory-adjustments', builder: (context, state) => const InventoryAdjustmentsScreen()),
        GoRoute(path: '/payments', name: 'payments', builder: (context, state) => const PaymentListScreen()),
        GoRoute(path: '/journal-entries', name: 'journal-entries', builder: (context, state) => const JournalEntriesScreen()),
        GoRoute(path: '/banking', name: 'banking', builder: (context, state) => const BankingScreen()),
        GoRoute(path: '/bank-reconciliation', name: 'bank-reconciliation', builder: (context, state) => const BankReconciliationScreen()),
        GoRoute(path: '/cash-book', name: 'cash-book', builder: (context, state) => const CashBookScreen()),
        GoRoute(path: '/chart-of-accounts', name: 'chart-of-accounts', builder: (context, state) => const ChartOfAccountsScreen()),
        GoRoute(path: '/reports', name: 'reports', builder: (context, state) => const ReportsScreen()),
        GoRoute(path: '/sales-analytics', name: 'sales-analytics', builder: (context, state) => const SalesAnalyticsScreen()),
        GoRoute(path: '/gst-returns', name: 'gst-returns', builder: (context, state) => const GstReturnsScreen()),
        GoRoute(path: '/eway-bills', name: 'eway-bills', builder: (context, state) => const EwayBillsScreen()),
        GoRoute(path: '/audit-log', name: 'audit-log', builder: (context, state) => const AuditLogScreen()),
        GoRoute(path: '/settings', name: 'settings', builder: (context, state) => const SettingsScreen()),
        GoRoute(path: '/recurring-invoices', name: 'recurring-invoices', builder: (context, state) => const RecurringInvoiceListScreen()),
        GoRoute(path: '/recurring-invoices/create', name: 'create-recurring-invoice', builder: (context, state) => const RecurringInvoiceFormScreen()),
        GoRoute(path: '/recurring-invoices/:id', name: 'recurring-invoice-detail', builder: (context, state) => RecurringInvoiceDetailScreen(id: state.pathParameters['id']!)),
        GoRoute(path: '/terms-templates', name: 'terms-templates', builder: (context, state) => const TermsTemplatesScreen()),
      ],
    ),
  ],
);
