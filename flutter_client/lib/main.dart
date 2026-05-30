import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
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
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/views/auth/login_view.dart';
import 'package:flutter_client/views/shared/shell_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';

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
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MainAppShell(),
    );
  }
}

class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    ApiClient.onSessionExpired = () {
      if (mounted) {
        context.read<AuthProvider>().logout();
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginView()),
          (route) => false,
        );
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Apex Books',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: authProvider.isLoading
          ? const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            )
          : authProvider.isAuthenticated
              ? const ShellView()
              : const LoginView(),
    );
  }
}
