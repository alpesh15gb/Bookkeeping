/// The root [MaterialApp] — wires the theme controller and the auth-aware
/// [GoRouter] together.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/theme/responsive.dart';
import '../core/routing/router.dart';

class ApexApp extends ConsumerWidget {
  const ApexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ApexBooks',
      debugShowCheckedModeBanner: false,
      theme: apexLightTheme(),
      darkTheme: apexDarkTheme(),
      themeMode: themeMode.toMaterial(),
      routerConfig: router,
      builder: (context, child) {
        // Respect system text scaling for WCAG 1.4.4 compliance (200%).
        // If layout issues appear at large scales, fix the layout rather than
        // clamping — a clamp below 2.0 is an accessibility violation.
        return ResponsiveLayout(
          child: MediaQuery(
            data: MediaQuery.of(context),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
