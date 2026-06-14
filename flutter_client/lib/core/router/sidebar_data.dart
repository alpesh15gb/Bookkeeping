import 'package:flutter/material.dart';

class SidebarItem {
  final String label;
  final IconData icon;
  final String route;
  final String? badge;

  const SidebarItem({
    required this.label,
    required this.icon,
    required this.route,
    this.badge,
  });
}

class SidebarSection {
  final String label;
  final List<SidebarItem> items;

  const SidebarSection({
    required this.label,
    required this.items,
  });
}

const sidebarSections = [
  SidebarSection(
    label: 'Sales',
    items: [
      SidebarItem(
        label: 'Invoices',
        icon: Icons.receipt_long,
        route: '/invoices',
      ),
      SidebarItem(
        label: 'Estimates',
        icon: Icons.request_quote,
        route: '/estimates',
      ),
      SidebarItem(
        label: 'Sales Orders',
        icon: Icons.shopping_cart,
        route: '/sales-orders',
      ),
      SidebarItem(
        label: 'Credit Notes',
        icon: Icons.compare_arrows,
        route: '/credit-notes',
      ),
    ],
  ),
  SidebarSection(
    label: 'Purchases',
    items: [
      SidebarItem(
        label: 'Vendor Bills',
        icon: Icons.receipt,
        route: '/bills',
      ),
      SidebarItem(
        label: 'Expenses',
        icon: Icons.money_off,
        route: '/expenses',
      ),
      SidebarItem(
        label: 'Purchase Orders',
        icon: Icons.shopping_bag,
        route: '/purchase-orders',
      ),
      SidebarItem(
        label: 'Debit Notes',
        icon: Icons.compare_arrows,
        route: '/debit-notes',
      ),
      SidebarItem(
        label: 'Returns',
        icon: Icons.assignment_return,
        route: '/returns',
      ),
    ],
  ),
  SidebarSection(
    label: 'People & Inventory',
    items: [
      SidebarItem(
        label: 'Parties',
        icon: Icons.people,
        route: '/parties',
      ),
      SidebarItem(
        label: 'Products',
        icon: Icons.inventory_2,
        route: '/products',
      ),
      SidebarItem(
        label: 'Delivery Challans',
        icon: Icons.local_shipping,
        route: '/delivery-challans',
      ),
      SidebarItem(
        label: 'Inventory Adj.',
        icon: Icons.tune,
        route: '/inventory-adjustments',
      ),
    ],
  ),
  SidebarSection(
    label: 'Money',
    items: [
      SidebarItem(
        label: 'Payments',
        icon: Icons.payments,
        route: '/payments',
      ),
      SidebarItem(
        label: 'Journal Entries',
        icon: Icons.book,
        route: '/journal-entries',
      ),
      SidebarItem(
        label: 'Banking',
        icon: Icons.account_balance_wallet,
        route: '/banking',
      ),
      SidebarItem(
        label: 'Bank Reconciliation',
        icon: Icons.account_balance,
        route: '/bank-reconciliation',
      ),
      SidebarItem(
        label: 'Cash Book',
        icon: Icons.book_online,
        route: '/cash-book',
      ),
    ],
  ),
  SidebarSection(
    label: 'Reports & Compliance',
    items: [
      SidebarItem(
        label: 'Financial Reports',
        icon: Icons.bar_chart,
        route: '/reports',
      ),
      SidebarItem(
        label: 'Sales Analytics',
        icon: Icons.analytics,
        route: '/sales-analytics',
      ),
      SidebarItem(
        label: 'GST Returns',
        icon: Icons.description,
        route: '/gst-returns',
      ),
      SidebarItem(
        label: 'E-Way Bills',
        icon: Icons.local_shipping,
        route: '/eway-bills',
      ),
      SidebarItem(
        label: 'Audit Log',
        icon: Icons.history,
        route: '/audit-log',
      ),
    ],
  ),
  SidebarSection(
    label: 'Settings',
    items: [
      SidebarItem(
        label: 'Settings',
        icon: Icons.settings,
        route: '/settings',
      ),
    ],
  ),
];
