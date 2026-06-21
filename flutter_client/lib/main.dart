import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/providers/expense_provider.dart';
import 'package:flutter_client/providers/payment_provider.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/providers/dashboard_provider.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/providers/eway_bill_provider.dart';
import 'package:flutter_client/providers/bank_reconciliation_provider.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/providers/misc_provider.dart';
import 'package:flutter_client/providers/sales_analytics_provider.dart';
import 'package:flutter_client/providers/cash_book_provider.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/providers/theme_provider.dart';
import 'package:flutter_client/providers/estimate_provider.dart';
import 'package:flutter_client/providers/credit_note_provider.dart';
import 'package:flutter_client/providers/purchase_order_provider.dart';
import 'package:flutter_client/providers/recurring_invoice_provider.dart';
import 'package:flutter_client/providers/terms_template_provider.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
import 'package:flutter_client/core/sync_manager.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
        ChangeNotifierProvider(create: (_) => BillProvider()),
        ChangeNotifierProvider(create: (_) => AccountingProvider()),
        ChangeNotifierProvider(create: (_) => DocumentProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        ChangeNotifierProvider(create: (_) => BankingProfileProvider()),
        ChangeNotifierProvider(create: (_) => EwayBillProvider()),
        ChangeNotifierProvider(create: (_) => BankReconciliationProvider()),
        ChangeNotifierProvider(create: (_) => DeliveryChallanProvider()),
        ChangeNotifierProvider(create: (_) => InventoryAdjustmentProvider()),
        ChangeNotifierProvider(create: (_) => MiscProvider()),
        ChangeNotifierProvider(create: (_) => SalesAnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => CashBookProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => FinancialYearProvider()),
        ChangeNotifierProvider(create: (_) => EstimateProvider()),
        ChangeNotifierProvider(create: (_) => CreditNoteProvider()),
        ChangeNotifierProvider(create: (_) => PurchaseOrderProvider()),
        ChangeNotifierProvider(create: (_) => RecurringInvoiceProvider()),
        ChangeNotifierProvider(create: (_) => TermsTemplateProvider()),
        ChangeNotifierProvider(create: (_) => SyncManager()),
      ],
      child: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  @override
  void initState() {
    super.initState();
    ApiClient.onSessionExpired = () {
      if (mounted) {
        appRouter.go('/login');
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      title: 'ApexBooks',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeProvider.themeMode,
      routerConfig: appRouter,
    );
  }
}
