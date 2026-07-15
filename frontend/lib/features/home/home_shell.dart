import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/features/auth/data/models/membership_models.dart';

import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'package:apexbooks/features/auth/presentation/auth_routes.dart'
    as auth_routes;
import 'package:apexbooks/core/search/command_palette.dart';
import 'package:apexbooks/features/screens.dart';
import 'home_shell_widgets.dart';

// Types for flattened nav
sealed class _NavEntry {
  const _NavEntry();
}

class _NavHeader extends _NavEntry {
  const _NavHeader(this.label);
  final String label;
}

class _NavItem extends _NavEntry {
  const _NavItem(this.idx, this.name, this.icon);
  final int idx;
  final String name;
  final IconData icon;
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selIdx = 0;
  bool _coll = false;
  List<(String, IconData, String, Widget)> get _screens {
    final membership = ref.watch(authControllerProvider).activeMembership;
    final gstEnabled =
        membership?.taxMode != null && membership!.taxMode != 'NON_GST';
    return getScreensList(gstEnabled: gstEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final company = ref.watch(authControllerProvider).activeMembership;
    final userEmail =
        ref.watch(authControllerProvider).user?.email ?? 'user@company.com';

    final groupedNavs = <String, List<(int, String, IconData)>>{};
    for (int i = 0; i < _screens.length; i++) {
      groupedNavs.putIfAbsent(_screens[i].$3, () => []).add((
        i,
        _screens[i].$1,
        _screens[i].$2,
      ));
    }

    return CommandPaletteShortcut(
      child: ResponsiveLayout(
        mobile: _buildMobileLayout(
          colors,
          groupedNavs,
          userEmail,
          company,
          context,
        ),
        tablet: _buildTabletLayout(
          colors,
          groupedNavs,
          userEmail,
          company,
          context,
        ),
        desktop: _buildDesktopLayout(
          colors,
          groupedNavs,
          userEmail,
          company,
          context,
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    ApexColors colors,
    Map<String, List<(int, String, IconData)>> groupedNavs,
    String userEmail,
    Membership? company,
    BuildContext context,
  ) {
    final dashboardIndex = _screens.indexWhere((s) => s.$1 == 'Dashboard');
    final invoiceIndex = _screens.indexWhere((s) => s.$1 == 'Invoices');
    final contactsIndex = _screens.indexWhere((s) => s.$1 == 'Contacts');
    final mobileDestination = _selIdx == dashboardIndex
        ? 0
        : _selIdx == invoiceIndex
        ? 1
        : _selIdx == contactsIndex
        ? 2
        : 3;
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: _buildDrawer(
            colors,
            groupedNavs,
            userEmail,
            company?.displayName ?? 'ApexBooks ERP',
            company?.role.label,
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu_rounded, color: colors.onPrimary),
            tooltip: 'Open menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          company?.displayName ?? 'ApexBooks',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.onPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: colors.onPrimary),
            tooltip: 'Search',
            onPressed: () => CommandPalette.show(context),
          ),
          IconButton(
            icon: Icon(
              Icons.notifications_none_rounded,
              color: colors.onPrimary,
            ),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
        ],
      ),
      body: _screens[_selIdx].$4,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickCreate(context),
        tooltip: 'Create',
        child: const Icon(Icons.add_rounded),
      ),
      bottomNavigationBar: Builder(
        builder: (scaffoldContext) => NavigationBar(
          selectedIndex: mobileDestination,
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) {
            if (index == 0 && dashboardIndex >= 0) {
              setState(() => _selIdx = dashboardIndex);
            } else if (index == 1 && invoiceIndex >= 0) {
              setState(() => _selIdx = invoiceIndex);
            } else if (index == 2 && contactsIndex >= 0) {
              setState(() => _selIdx = contactsIndex);
            } else if (index == 3) {
              Scaffold.of(scaffoldContext).openDrawer();
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Invoices',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_alt_rounded),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_rounded),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout(
    ApexColors colors,
    Map<String, List<(int, String, IconData)>> groupedNavs,
    String userEmail,
    Membership? company,
    BuildContext context,
  ) {
    final navEntries = <_NavEntry>[
      for (final entry in groupedNavs.entries) ...[
        _NavHeader(entry.key),
        for (final item in entry.value) _NavItem(item.$1, item.$2, item.$3),
      ],
    ];
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: _buildDrawer(
            colors,
            groupedNavs,
            userEmail,
            company?.displayName ?? 'ApexBooks ERP',
            company?.role.label,
          ),
        ),
      ),
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _coll ? 64 : 200,
            color: colors.surfaceMuted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: ApexSpacing.sm),
                IconButton(
                  icon: Icon(
                    _coll ? Icons.menu_open_rounded : Icons.menu_rounded,
                    size: 20,
                  ),
                  tooltip: 'Toggle menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                const SizedBox(height: ApexSpacing.sm),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    itemCount: navEntries.length,
                    itemBuilder: (context, i) {
                      final entry = navEntries[i];
                      return switch (entry) {
                        _NavHeader(:final label) =>
                          !_coll
                              ? Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    ApexSpacing.sm,
                                    ApexSpacing.md,
                                    ApexSpacing.sm,
                                    ApexSpacing.xs,
                                  ),
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontSize: 9,
                                          color: colors.textMuted,
                                          letterSpacing: 1.0,
                                        ),
                                  ),
                                )
                              : const SizedBox(height: ApexSpacing.xs),
                        _NavItem(:final idx, :final name, :final icon) =>
                          _buildNavItem(
                            idx,
                            name,
                            icon,
                            colors,
                            compact: _coll,
                          ),
                      };
                    },
                  ),
                ),
                const Divider(height: 1),
                if (!_coll)
                  buildProfileBox(context, false, colors, userEmail, () async {
                    await ref.read(authControllerProvider.notifier).signOut();
                    if (mounted) context.go(auth_routes.login);
                  }, role: company?.role.label),
                IconButton(
                  icon: Icon(
                    _coll
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _coll = !_coll),
                ),
                const SizedBox(height: ApexSpacing.sm),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                buildToolbar(
                  context,
                  colors,
                  company?.displayName ?? 'ApexBooks',
                  () => CommandPalette.show(context),
                  () => _showQuickCreate(context),
                ),
                Expanded(child: _screens[_selIdx].$4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    ApexColors colors,
    Map<String, List<(int, String, IconData)>> groupedNavs,
    String userEmail,
    Membership? company,
    BuildContext context,
  ) {
    final navEntries = <_NavEntry>[
      for (final entry in groupedNavs.entries) ...[
        _NavHeader(entry.key),
        for (final item in entry.value) _NavItem(item.$1, item.$2, item.$3),
      ],
    ];
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _coll ? 72 : 230,
            color: colors.surfaceMuted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: ApexSpacing.lg),
                selectorWidget(
                  context,
                  _coll,
                  colors,
                  company?.displayName ?? 'ApexBooks ERP',
                ),
                const SizedBox(height: ApexSpacing.lg),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: navEntries.length,
                    itemBuilder: (context, i) {
                      final entry = navEntries[i];
                      return switch (entry) {
                        _NavHeader(:final label) =>
                          !_coll
                              ? Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    ApexSpacing.md,
                                    ApexSpacing.lg,
                                    ApexSpacing.md,
                                    6,
                                  ),
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontSize: 10,
                                          color: colors.textMuted,
                                          letterSpacing: 1.1,
                                        ),
                                  ),
                                )
                              : const SizedBox(height: ApexSpacing.sm),
                        _NavItem(:final idx, :final name, :final icon) =>
                          _buildNavItem(
                            idx,
                            name,
                            icon,
                            colors,
                            compact: _coll,
                          ),
                      };
                    },
                  ),
                ),
                const Divider(height: 1),
                buildProfileBox(context, _coll, colors, userEmail, () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (mounted) context.go(auth_routes.login);
                }, role: company?.role.label),
                IconButton(
                  icon: Icon(
                    _coll
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _coll = !_coll),
                ),
                const SizedBox(height: ApexSpacing.md),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                buildToolbar(
                  context,
                  colors,
                  company?.displayName ?? 'ApexBooks',
                  () => CommandPalette.show(context),
                  () => _showQuickCreate(context),
                ),
                Expanded(child: _screens[_selIdx].$4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickCreate(BuildContext context) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Create',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Start common entries without leaving your current work.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _quickChoice(
                    sheetContext,
                    'invoice',
                    'Sales Invoice',
                    Icons.receipt_long_outlined,
                    'Ctrl+K → New Invoice',
                  ),
                  _quickChoice(
                    sheetContext,
                    'receipt',
                    'Payment Receipt',
                    Icons.payments_outlined,
                    'Allocate customer payment',
                  ),
                  _quickChoice(
                    sheetContext,
                    'expense',
                    'Expense',
                    Icons.account_balance_wallet_outlined,
                    'Fast cash/bank expense',
                  ),
                  _quickChoice(
                    sheetContext,
                    'scan_bill',
                    'Scan Purchase Bill',
                    Icons.document_scanner_outlined,
                    'OCR image or PDF',
                  ),
                  _quickChoice(
                    sheetContext,
                    'bill',
                    'Purchase Bill',
                    Icons.shopping_cart_checkout_outlined,
                    'Manual vendor bill',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selection == null) return;
    final screen = switch (selection) {
      'invoice' => const InvoiceFormScreen(),
      'receipt' => const PaymentFormScreen(),
      'expense' => const ExpenseFormScreen(),
      'scan_bill' => const BillScanScreen(),
      _ => const BillFormScreen(),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _quickChoice(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    String subtitle,
  ) {
    final colors = apexColors(context);
    return SizedBox(
      width: 280,
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
          side: BorderSide(color: colors.border),
        ),
        leading: Icon(icon, color: colors.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.of(context).pop(value),
      ),
    );
  }

  Widget _buildDrawer(
    ApexColors colors,
    Map<String, List<(int, String, IconData)>> groupedNavs,
    String userEmail,
    String companyName,
    String? role,
  ) {
    final navEntries = <_NavEntry>[
      for (final entry in groupedNavs.entries) ...[
        _NavHeader(entry.key),
        for (final item in entry.value) _NavItem(item.$1, item.$2, item.$3),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ApexSpacing.lg),
        selectorWidget(context, false, colors, companyName),
        const SizedBox(height: ApexSpacing.lg),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: navEntries.length,
            itemBuilder: (context, i) {
              final entry = navEntries[i];
              return switch (entry) {
                _NavHeader(:final label) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    ApexSpacing.md,
                    ApexSpacing.lg,
                    ApexSpacing.md,
                    6,
                  ),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: colors.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                _NavItem(:final idx, :final name, :final icon) => _buildNavItem(
                  idx,
                  name,
                  icon,
                  colors,
                ),
              };
            },
          ),
        ),
        const Divider(height: 1),
        buildProfileBox(context, false, colors, userEmail, () async {
          await ref.read(authControllerProvider.notifier).signOut();
          if (mounted) context.go(auth_routes.login);
        }, role: role),
      ],
    );
  }

  Widget _buildNavItem(
    int idx,
    String name,
    IconData icon,
    ApexColors colors, {
    bool compact = false,
  }) {
    final active = _selIdx == idx;
    final tile = Padding(
      padding: EdgeInsets.symmetric(
        vertical: ApexSpacing.xs,
        horizontal: ApexSpacing.xs,
      ),
      child: InkWell(
        onTap: () {
          setState(() => _selIdx = idx);
          // Close drawer when in drawer mode
          Navigator.of(context).maybePop();
        },
        borderRadius: BorderRadius.circular(ApexRadius.sm),
        child: Container(
          padding: EdgeInsets.only(
            left: compact ? 10 : 9,
            right: 16,
            top: 12,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: active
                ? colors.primaryContainer.withValues(alpha: 0.30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(ApexRadius.sm),
            border: Border(
              left: BorderSide(
                color: active ? colors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? colors.primary : colors.textSecondary,
              ),
              if (!compact) ...[
                const SizedBox(width: ApexSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? colors.textPrimary : colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return compact
        ? Tooltip(
            message: name,
            waitDuration: const Duration(milliseconds: 400),
            child: tile,
          )
        : tile;
  }
}
