/// Chart of Accounts list screen — a tree view with expand/collapse.
///
/// Unlike the flat-table list screens (Contacts, Products), COA renders a
/// hierarchy because accounts have parent/child relationships. The data layer
/// still reuses BaseCrudController + BaseRepository (which return a flat array
/// ordered by code); only the presentation builds and renders the tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/search_bar.dart';
import '../data/models/account.dart';
import 'account_controller.dart';
import 'account_form_screen.dart';
import 'account_detail_screen.dart';

class AccountListScreen extends ConsumerStatefulWidget {
  const AccountListScreen({super.key});

  @override
  ConsumerState<AccountListScreen> createState() => _AccountListScreenState();
}

class _AccountListScreenState extends ConsumerState<AccountListScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  AccountType? _typeFilter;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(accountControllerProvider.notifier)
          .load(const ListQuery(limit: 1000)),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Account> get _allAccounts {
    final state = ref.read(accountControllerProvider);
    return switch (state) {
      ListData<Account>(:final paged) => paged.items,
      _ => const [],
    };
  }

  void _openForm([Account? account]) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                AccountFormScreen(account: account, existing: _allAccounts),
          ),
        )
        .then((_) => _reload());
  }

  void _openDetail(Account a) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                AccountDetailScreen(account: a, allAccounts: _allAccounts),
          ),
        )
        .then((_) => _reload());
  }

  void _reload() {
    ref
        .read(accountControllerProvider.notifier)
        .load(const ListQuery(limit: 1000));
  }

  bool _matches(Account a) {
    if (_typeFilter != null && a.accountType != _typeFilter) return false;
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return a.name.toLowerCase().contains(q) ||
        a.code.toLowerCase().contains(q) ||
        (a.accountGroup?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chart of Accounts'),
        actions: [
          PermissionGate(
            permission: Permissions.accountsManage,
            child: IconButton(
              tooltip: 'Seed standard accounts',
              icon: const Icon(Icons.auto_fix_high_outlined),
              onPressed: () => _confirmSeed(context),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: switch (state) {
        ListLoading() => ShimmerSkeleton(
          child: Column(
            children: [
              for (int i = 0; i < 6; i++) const TableRowSkeleton(columns: 4),
            ],
          ),
        ),
        ListEmpty() => EmptyState(
          icon: Icons.account_tree_outlined,
          title: 'No accounts yet',
          subtitle: 'Seed the standard chart or create your first account.',
          actionLabel: 'Seed Standard Accounts',
          onAction: () => _confirmSeed(context),
        ),
        ListError(:final message) => ErrorView(
          message: message,
          onRetry: _reload,
        ),
        ListData<Account>(:final paged) => _chartBody(paged.items),
        _ => const SizedBox.shrink(),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Account'),
      ),
    );
  }

  Widget _chartBody(List<Account> accounts) {
    final fmt = ref.read(numberFormatterProvider);
    final colors = apexColors(context);
    final tree = buildAccountTree(accounts);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            children: [
              ApexSearchBar(
                controller: _searchCtrl,
                hintText: 'Search by code, name or group…',
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip(null, 'All'),
                    for (final t in AccountType.values)
                      _filterChip(t, t.displayLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Container(
          color: colors.surfaceMuted,
          padding: const EdgeInsets.fromLTRB(52, 8, 16, 8),
          child: Row(
            children: [
              SizedBox(width: 70, child: Text('CODE', style: _thStyle(colors))),
              const SizedBox(width: 8),
              Expanded(child: Text('ACCOUNT', style: _thStyle(colors))),
              SizedBox(
                width: 120,
                child: Text(
                  'BALANCE',
                  textAlign: TextAlign.right,
                  style: _thStyle(colors),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 84, child: Text('TYPE', style: _thStyle(colors))),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: tree.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  subtitle: 'Try a different search or filter.',
                )
              : ListView.builder(
                  itemCount: tree.length,
                  itemBuilder: (_, i) => _treeTile(tree[i], 0, fmt, colors),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(AccountType? type, String label) {
    final selected = _typeFilter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _typeFilter = selected ? null : type),
      ),
    );
  }

  Widget _treeTile(
    AccountNode node,
    int depth,
    NumberFormatter fmt,
    ApexColors colors,
  ) {
    final a = node.account;
    final matches = _matches(a);
    final visible = matches || node.anyMatch(_matches);
    if (!visible) return const SizedBox.shrink();

    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expanded.contains(a.id);

    return Column(
      children: [
        InkWell(
          onTap: () => _openDetail(a),
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + depth * 24,
              right: 16,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                if (hasChildren)
                  InkWell(
                    borderRadius: BorderRadius.circular(ApexRadius.xl),
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _expanded.remove(a.id);
                      } else {
                        _expanded.add(a.id);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isExpanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 28),
                Icon(a.accountType.icon, size: 18, color: colors.textSecondary),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    a.code,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    fmt.currency(node.totalBalance),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: a.isActive ? null : colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _typeBadge(a.accountType, colors),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          ...node.children.map((c) => _treeTile(c, depth + 1, fmt, colors)),
      ],
    );
  }

  TextStyle _thStyle(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );

  Widget _typeBadge(AccountType t, ApexColors colors) {
    final tone = switch (t) {
      AccountType.asset => colors.info,
      AccountType.liability => colors.warning,
      AccountType.equity => colors.primary,
      AccountType.revenue => colors.success,
      AccountType.expense => colors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ApexRadius.pill),
      ),
      child: Text(
        t.displayLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }

  Future<void> _confirmSeed(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed Standard Accounts'),
        content: const Text(
          'This creates the standard ApexBooks chart of accounts '
          '(Cash, Bank, Receivables, Inventory, GST, Sales, Purchases, etc.). '
          'Existing accounts with the same code are skipped. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Seed'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(accountControllerProvider.notifier).seedDefaults(context);
    }
  }
}
