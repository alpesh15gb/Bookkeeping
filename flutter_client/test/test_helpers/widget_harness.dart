import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/router/shell_screen.dart';
import 'package:flutter_client/core/theme/app_theme.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/providers/dashboard_provider.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import '../fake_repositories/fake_dashboard_provider.dart';

Widget buildWidgetHarness(
  Widget child, {
  Size size = const Size(390, 844),
  DashboardProvider? dashboardProvider,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(restoreOnCreate: false),
        ),
        ChangeNotifierProvider<FinancialYearProvider>(
          create: (_) => FinancialYearProvider(),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => dashboardProvider ?? FakeDashboardProvider(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
}

Widget buildShellHarness({
  required Size size,
  String initialLocation = '/dashboard',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const ColoredBox(
              color: Colors.white,
              child: SizedBox.expand(child: Text('Dashboard content')),
            ),
          ),
          GoRoute(
            path: '/invoices/create',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/invoices',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/bills',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/parties',
            builder: (context, state) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      ),
    ],
  );

  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(restoreOnCreate: false),
        ),
        ChangeNotifierProvider<FinancialYearProvider>(
          create: (_) => FinancialYearProvider(),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => FakeDashboardProvider(),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
}
