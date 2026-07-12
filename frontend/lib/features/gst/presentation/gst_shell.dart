/// GST Hub — tabbed shell housing the GST Dashboard, GSTR-1, GSTR-3B,
/// and Returns screens.
library;

import 'package:flutter/material.dart';
import '../../home/home_shell_widgets.dart';
import 'gst_dashboard_screen.dart';
import 'gstr1_screen.dart';
import 'gstr3b_screen.dart';
import 'gst_returns_screen.dart';

class GstShell extends StatelessWidget {
  const GstShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const HubTabWidget(
      tabs: [
        'Dashboard',
        'GSTR-1',
        'GSTR-3B',
        'Returns',
      ],
      views: [
        GstDashboardScreen(),
        Gstr1Screen(),
        Gstr3bScreen(),
        GstReturnsScreen(),
      ],
    );
  }
}
