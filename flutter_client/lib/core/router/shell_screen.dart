import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../design_system/tokens/colors.dart';
import '../../design_system/tokens/typography.dart';
import '../../design_system/tokens/spacing.dart';
import '../../providers/auth_provider.dart';
import '../../providers/financial_year_provider.dart';
import '../../providers/settings_provider.dart';
import 'sidebar_data.dart';

class ShellScreen extends StatefulWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  bool _isSidebarExpanded = true;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;

    if (isMobile) {
      return _buildMobileLayout();
    }

    return _buildDesktopLayout(isTablet);
  }

  Widget _buildDesktopLayout(bool isTablet) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded
                ? (isTablet ? 200 : AppSpacing.sidebarWidth)
                : AppSpacing.sidebarCollapsedWidth,
            child: _buildSidebar(isTablet),
          ),
          // Main content
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Container(
                    color: AppColors.gray50,
                    padding: const EdgeInsets.all(AppSpacing.pagePadding),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: _buildMobileAppBar(),
      drawer: _buildMobileDrawer(),
      body: widget.child,
      bottomNavigationBar: _buildMobileBottomNav(),
      floatingActionButton: _buildMobileFAB(),
    );
  }

  Widget _buildSidebar(bool isTablet) {
    return Container(
      color: AppColors.sidebarBg,
      child: Column(
        children: [
          // Brand header
          Container(
            padding: EdgeInsets.all(isTablet ? AppSpacing.md : AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Center(
                    child: Text(
                      'A',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (_isSidebarExpanded && !isTablet) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ApexBooks',
                          style: AppTypography.headlineSmall.copyWith(
                            color: AppColors.sidebarTextActive,
                          ),
                        ),
                        Text(
                          'Accounting Suite',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.sidebarSection,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: AppColors.sidebarHover, height: 1),
          // Navigation
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: _buildNavItems(isTablet),
            ),
          ),
          // Footer
          _buildSidebarFooter(isTablet),
        ],
      ),
    );
  }

  List<Widget> _buildNavItems(bool isTablet) {
    final items = <Widget>[];

    // Dashboard
    items.add(_buildNavItem(
      icon: Icons.dashboard_rounded,
      label: 'Dashboard',
      route: '/dashboard',
      isSelected: GoRouterState.of(context).uri.path == '/dashboard',
      isCompact: !_isSidebarExpanded || isTablet,
    ));

    // Sections
    for (final section in sidebarSections) {
      items.add(_buildSectionHeader(
        label: section.label,
        isCompact: !_isSidebarExpanded || isTablet,
      ));

      for (final item in section.items) {
        items.add(_buildNavItem(
          icon: item.icon,
          label: item.label,
          route: item.route,
          isSelected: GoRouterState.of(context).uri.path == item.route,
          isCompact: !_isSidebarExpanded || isTablet,
          badge: item.badge,
        ));
      }
    }

    return items;
  }

  Widget _buildSectionHeader({required String label, required bool isCompact}) {
    if (isCompact) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.sidebarSection,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required String route,
    required bool isSelected,
    required bool isCompact,
    String? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: isSelected ? AppColors.sidebarHover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: () => context.go(route),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          hoverColor: AppColors.sidebarHover,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? AppSpacing.sm : AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? AppColors.sidebarTextActive
                      : AppColors.sidebarText,
                ),
                if (!isCompact) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: isSelected
                            ? AppColors.sidebarTextActive
                            : AppColors.sidebarText,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        badge,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(bool isTablet) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final userName = user?.fullName ?? 'User';
    final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

    return Container(
      padding: EdgeInsets.all(isTablet ? AppSpacing.sm : AppSpacing.lg),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.sidebarHover),
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  _isSidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
                  color: AppColors.sidebarText,
                ),
              ),
            ),
          ),
          if (!isTablet && _isSidebarExpanded) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    userInitial,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.sidebarTextActive,
                        ),
                      ),
                      Text(
                        user?.email ?? '',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.sidebarSection,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showLogoutDialog(context),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.logout, size: 16, color: AppColors.sidebarText),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthProvider>().logout();
              context.go('/login');
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final currentPath = GoRouterState.of(context).uri.path;
    final currentTitle = _getTitleFromRoute(currentPath);

    return Container(
      height: AppSpacing.topBarHeight,
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(
            currentTitle,
            style: AppTypography.headlineLarge,
          ),
          const Spacer(),
          // Quick actions
          _buildQuickActions(),
          const SizedBox(width: AppSpacing.md),
          // Search
          _buildSearchButton(),
          const SizedBox(width: AppSpacing.md),
          // FY selector
          _buildFySelector(),
          const SizedBox(width: AppSpacing.md),
          // User avatar
          _buildUserAvatar(),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _buildActionButton(
          label: '+ Invoice',
          color: AppColors.primary,
          onTap: () => context.go('/invoices/create'),
        ),
        const SizedBox(width: AppSpacing.sm),
        _buildActionButton(
          label: '+ Payment',
          color: AppColors.success,
          onTap: () {},
        ),
        const SizedBox(width: AppSpacing.sm),
        _buildActionButton(
          label: '+ Expense',
          color: AppColors.error,
          onTap: () {},
        ),
        const SizedBox(width: AppSpacing.sm),
        _buildActionButton(
          label: '+ Bill',
          color: AppColors.warning,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    return Material(
      color: AppColors.gray50,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: () => _showCommandPalette(),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search, size: 18, color: AppColors.gray400),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Ctrl+K',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.gray400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFySelector() {
    final fyProvider = context.watch<FinancialYearProvider>();
    final activeYear = fyProvider.activeYear;
    final fyLabel = activeYear?.name ?? 'No FY';

    return GestureDetector(
      onTap: () => _showFYPicker(context, fyProvider),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              fyLabel,
              style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  void _showFYPicker(BuildContext context, FinancialYearProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('Financial Years', style: AppTypography.headlineMedium),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: provider.availableYears.length,
                  itemBuilder: (context, i) {
                    final year = provider.availableYears[i];
                    final isActive = provider.activeYear?.id == year.id;
                    return ListTile(
                      leading: Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      title: Text(year.name),
                      subtitle: Text('${year.startDate} - ${year.endDate}'),
                      trailing: isActive
                          ? const Icon(Icons.check_circle, color: AppColors.primary)
                          : null,
                      onTap: () {
                        provider.setActiveYear(year);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserAvatar() {
    final authProvider = context.watch<AuthProvider>();
    final userName = authProvider.currentUser?.fullName ?? 'U';
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primaryLight,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  void _showCommandPalette() {
    showDialog(
      context: context,
      builder: (context) => const CommandPaletteDialog(),
    );
  }

  String _getTitleFromRoute(String path) {
    if (path == '/dashboard') return 'Dashboard';
    if (path == '/invoices') return 'Invoices';
    if (path == '/invoices/create') return 'Create Invoice';
    if (path.startsWith('/invoices/')) return 'Invoice Detail';
    if (path == '/parties') return 'Parties';
    if (path.startsWith('/parties/')) return 'Party Detail';
    if (path == '/bills') return 'Vendor Bills';
    if (path == '/expenses') return 'Expenses';
    if (path == '/payments') return 'Payments';
    if (path == '/reports') return 'Reports';
    if (path == '/settings') return 'Settings';
    return 'ApexBooks';
  }

  // Mobile components
  PreferredSizeWidget _buildMobileAppBar() {
    return AppBar(
      title: const Text('ApexBooks'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _showCommandPalette(),
        ),
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildMobileDrawer() {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final userName = user?.fullName ?? 'User';
    final userEmail = user?.email ?? '';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(userName),
              accountEmail: Text(userEmail),
              currentAccountPicture: CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                  style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dashboard),
                    title: const Text('Dashboard'),
                    selected: GoRouterState.of(context).uri.path == '/dashboard',
                    onTap: () {
                      context.go('/dashboard');
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                  ...sidebarSections.map((section) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          section.label.toUpperCase(),
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.gray500,
                          ),
                        ),
                      ),
                      ...section.items.map((item) => ListTile(
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        onTap: () {
                          context.go(item.route);
                          Navigator.pop(context);
                        },
                      )),
                    ],
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.gray500,
      currentIndex: _getMobileNavIndex(),
      onTap: (index) => _onMobileNavTap(index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long),
          label: 'Invoices',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people),
          label: 'Parties',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart),
          label: 'Reports',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.menu),
          label: 'More',
        ),
      ],
    );
  }

  int _getMobileNavIndex() {
    final path = GoRouterState.of(context).uri.path;
    if (path == '/dashboard') return 0;
    if (path.startsWith('/invoices')) return 1;
    if (path.startsWith('/parties')) return 2;
    if (path.startsWith('/reports')) return 3;
    return 4;
  }

  void _onMobileNavTap(int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/invoices');
        break;
      case 2:
        context.go('/parties');
        break;
      case 3:
        context.go('/reports');
        break;
      case 4:
        Scaffold.of(context).openDrawer();
        break;
    }
  }

  Widget _buildMobileFAB() {
    return FloatingActionButton(
      onPressed: () => _showMobileQuickActions(),
      backgroundColor: AppColors.primary,
      child: const Icon(Icons.add, color: AppColors.white),
    );
  }

  void _showMobileQuickActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('New Invoice'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/invoices/create');
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt),
                title: const Text('New Bill'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.money_off),
                title: const Text('New Expense'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.payments),
                title: const Text('New Payment'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Add Party'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Command Palette Dialog
class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({super.key});

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;

  final List<CommandPaletteItem> _items = [
    CommandPaletteItem('Dashboard', Icons.dashboard, '/dashboard'),
    CommandPaletteItem('Create Invoice', Icons.add_circle, '/invoices/create'),
    CommandPaletteItem('Invoices', Icons.receipt_long, '/invoices'),
    CommandPaletteItem('Vendor Bills', Icons.receipt, '/bills'),
    CommandPaletteItem('Expenses', Icons.money_off, '/expenses'),
    CommandPaletteItem('Payments', Icons.payments, '/payments'),
    CommandPaletteItem('Parties', Icons.people, '/parties'),
    CommandPaletteItem('Products', Icons.inventory_2, '/products'),
    CommandPaletteItem('Reports', Icons.bar_chart, '/reports'),
    CommandPaletteItem('Settings', Icons.settings, '/settings'),
  ];

  List<CommandPaletteItem> get _filteredItems {
    if (_controller.text.isEmpty) return _items;
    return _items
        .where((item) =>
            item.label.toLowerCase().contains(_controller.text.toLowerCase()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  hintText: 'Search commands...',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _selectedIndex = 0;
                  });
                },
                onSubmitted: (value) {
                  if (_filteredItems.isNotEmpty) {
                    context.go(_filteredItems[_selectedIndex].route);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  final isSelected = index == _selectedIndex;

                  return ListTile(
                    leading: Icon(
                      item.icon,
                      color: isSelected ? AppColors.primary : AppColors.gray500,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.gray700,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    tileColor:
                        isSelected ? AppColors.primary.withOpacity(0.1) : null,
                    onTap: () {
                      context.go(item.route);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.gray200)),
              ),
              child: Row(
                children: [
                  Text(
                    '↑↓ Navigate  •  Enter Select  •  Esc Close',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.gray400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommandPaletteItem {
  final String label;
  final IconData icon;
  final String route;

  const CommandPaletteItem(this.label, this.icon, this.route);
}
