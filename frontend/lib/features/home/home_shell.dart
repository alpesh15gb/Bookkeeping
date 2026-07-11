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
import 'home_shell_widgets.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selIdx = 0;
  bool _coll = false;
  late final List<(String, IconData, String, Widget)> _screens =
      getScreensList();

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
          colors, groupedNavs, userEmail, company, context,
        ),
        tablet: _buildTabletLayout(
          colors, groupedNavs, userEmail, company, context,
        ),
        desktop: _buildDesktopLayout(
          colors, groupedNavs, userEmail, company, context,
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
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: _buildDrawer(
            colors, groupedNavs, userEmail,
            company?.displayName ?? 'ApexBooks ERP',
            company?.role.label,
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu_rounded, color: colors.textPrimary),
            tooltip: 'Open menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          company?.displayName ?? 'ApexBooks',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: colors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: colors.textSecondary),
            tooltip: 'Search',
            onPressed: () => CommandPalette.show(context),
          ),
          IconButton(
            icon: Icon(Icons.notifications_none_rounded,
                color: colors.textSecondary),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: Icon(Icons.account_circle_outlined,
                  color: colors.textSecondary),
              tooltip: 'Sign out',
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).signOut();
                if (mounted) context.go(auth_routes.login);
              },
            ),
          ),
        ],
      ),
      body: _screens[_selIdx].$4,
    );
  }

  Widget _buildTabletLayout(
    ApexColors colors,
    Map<String, List<(int, String, IconData)>> groupedNavs,
    String userEmail,
    Membership? company,
    BuildContext context,
  ) {
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: _buildDrawer(
            colors, groupedNavs, userEmail,
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
                const SizedBox(height: 8),
                IconButton(
                  icon: Icon(
                    _coll ? Icons.menu_open_rounded : Icons.menu_rounded,
                    size: 20,
                  ),
                  tooltip: 'Toggle menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    children: [
                      for (final entry in groupedNavs.entries) ...[
                        if (!_coll)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: colors.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 4),
                        for (final item in entry.value)
                          _buildNavItem(
                            item.$1, item.$2, item.$3, colors,
                            compact: _coll,
                          ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (!_coll)
                  buildProfileBox(
                    context, false, colors, userEmail,
                    () async {
                      await ref
                          .read(authControllerProvider.notifier).signOut();
                      if (mounted) context.go(auth_routes.login);
                    },
                    role: company?.role.label,
                  ),
                IconButton(
                  icon: Icon(
                    _coll
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _coll = !_coll),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                buildToolbar(
                  context, colors,
                  company?.displayName ?? 'ApexBooks',
                  () => CommandPalette.show(context),
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
                const SizedBox(height: 16),
                selectorWidget(
                  context, _coll, colors,
                  company?.displayName ?? 'ApexBooks ERP',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final entry in groupedNavs.entries) ...[
                        if (!_coll)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colors.textMuted,
                                letterSpacing: 1.1,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 8),
                        for (final item in entry.value)
                          _buildNavItem(
                            item.$1, item.$2, item.$3, colors,
                            compact: _coll,
                          ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                buildProfileBox(
                  context, _coll, colors, userEmail,
                  () async {
                    await ref
                        .read(authControllerProvider.notifier).signOut();
                    if (mounted) context.go(auth_routes.login);
                  },
                  role: company?.role.label,
                ),
                IconButton(
                  icon: Icon(
                    _coll
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _coll = !_coll),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                buildToolbar(
                  context, colors,
                  company?.displayName ?? 'ApexBooks',
                  () => CommandPalette.show(context),
                ),
                Expanded(child: _screens[_selIdx].$4),
              ],
            ),
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        selectorWidget(context, false, colors, companyName),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final entry in groupedNavs.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colors.textMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                for (final item in entry.value)
                  _buildNavItem(item.$1, item.$2, item.$3, colors),
              ],
            ],
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
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
                const SizedBox(width: 12),
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
