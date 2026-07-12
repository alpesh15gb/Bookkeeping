/// Reports Hub — tabbed shell that houses the Sales Register, Purchase Register,
/// Customer Ledger, and Vendor Ledger screens.
///
/// Uses the same [HubTabWidget] pattern as the other hubs (Ledger, Purchases,
/// Inventory) in [home_shell_widgets.dart]. Each child screen provides its own
/// [PageHeader] and content, scrolled inside the shared [TabBarView].
library;

import 'package:flutter/material.dart';
import '../../home/home_shell_widgets.dart';
import 'sales_register_screen.dart';
import 'purchase_register_screen.dart';
import 'customer_ledger_screen.dart';
import 'vendor_ledger_screen.dart';

class ReportsShell extends StatelessWidget {
  const ReportsShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const HubTabWidget(
      tabs: [
        'Sales Register',
        'Purchase Register',
        'Customer Ledger',
        'Vendor Ledger',
      ],
      views: [
        SalesRegisterScreen(),
        PurchaseRegisterScreen(),
        CustomerLedgerScreen(),
        VendorLedgerScreen(),
      ],
    );
  }
}
