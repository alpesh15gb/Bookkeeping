import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/accounting/account_form_view.dart';
import 'dart:convert';

class AccountListView extends StatefulWidget {
  const AccountListView({super.key});

  @override
  State<AccountListView> createState() => _AccountListViewState();
}

class _AccountListViewState extends State<AccountListView> {
  final _searchCtrl = TextEditingController();
  String _typeFilter = 'ALL';
  bool _groupByCategory = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountingProvider>().fetchAccounts();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showForm() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: AccountFormView(
          onSuccess: () {
            Navigator.of(ctx).pop();
            context.read<AccountingProvider>().fetchAccounts();
          },
        ),
      ),
    );
  }

  Future<void> _seedDefaults() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Seed Default Accounts?',
      message: 'This will create all standard chart of accounts for your business. Existing accounts will not be duplicated.',
    );
    if (confirm != true) return;

    try {
      final response = await ApiClient().post(
        Uri.parse('${ApiClient.baseUrl}/masters/accounts/seed-defaults'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          AppToast.success(context, data['message'] ?? 'Accounts seeded');
          context.read<AccountingProvider>().fetchAccounts();
        }
      } else {
        if (mounted) AppToast.error(context, 'Failed to seed accounts');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountingProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _seedDefaults,
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('Seed Defaults'),
      ),
      body: Column(
        children: [
          // Header
          AppCard(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance, color: AppColors.brandNavy, size: 20),
                    const SizedBox(width: 8),
                    Text('Chart of Accounts', style: AppTextStyles.h2),
                    const Spacer(),
                    IconButton(
                      icon: Icon(_groupByCategory ? Icons.view_list : Icons.view_module, size: 20),
                      tooltip: _groupByCategory ? 'List View' : 'Group View',
                      onPressed: () => setState(() => _groupByCategory = !_groupByCategory),
                    ),
                    if (!isMobile)
                      AppButton(
                        label: 'New Account',
                        icon: Icons.add,
                        isPrimary: true,
                        onTap: _showForm,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Search bar
                AppInput(
                  controller: _searchCtrl,
                  hint: 'Search accounts by name or code...',
                  prefix: const Icon(Icons.search_rounded, size: 18),
                  suffix: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                // Type filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _typeChip('ALL', 'All'),
                      const SizedBox(width: 4),
                      _typeChip('ASSET', 'Assets'),
                      const SizedBox(width: 4),
                      _typeChip('LIABILITY', 'Liabilities'),
                      const SizedBox(width: 4),
                      _typeChip('EQUITY', 'Equity'),
                      const SizedBox(width: 4),
                      _typeChip('REVENUE', 'Revenue'),
                      const SizedBox(width: 4),
                      _typeChip('EXPENSE', 'Expenses'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Account list
          Expanded(
            child: _buildBody(provider, isMobile),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String type, String label) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _typeFilter == type,
      selectedColor: AppColors.brandNavy.withValues(alpha: 0.15),
      onSelected: (_) => setState(() => _typeFilter = type),
    );
  }

  Widget _buildBody(AccountingProvider provider, bool isMobile) {
    if (provider.isLoading) return const LoadingState(message: 'Loading accounts...');
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: () => provider.fetchAccounts());
    }

    final allAccounts = provider.accountsList ?? [];
    if (allAccounts.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'No accounts yet',
        subtitle: 'Tap "Seed Defaults" to create standard chart of accounts',
        actionLabel: 'Seed Defaults',
        onAction: _seedDefaults,
      );
    }

    // Filter by type
    final typeFiltered = _typeFilter == 'ALL'
        ? allAccounts
        : allAccounts.where((a) => a['account_type'] == _typeFilter).toList();

    // Filter by search
    final search = _searchCtrl.text.trim().toLowerCase();
    final filtered = search.isEmpty
        ? typeFiltered
        : typeFiltered.where((a) {
            final name = (a['name'] ?? '').toString().toLowerCase();
            final code = (a['code'] ?? '').toString().toLowerCase();
            final group = (a['account_group'] ?? '').toString().toLowerCase();
            return name.contains(search) || code.contains(search) || group.contains(search);
          }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text('No accounts match your filters', style: AppTextStyles.bodySmall),
      );
    }

    if (_groupByCategory) {
      return _buildGroupedView(filtered, isMobile);
    } else {
      return _buildListView(filtered, isMobile);
    }
  }

  Widget _buildGroupedView(List<dynamic> accounts, bool isMobile) {
    // Group by account_group
    final Map<String, List<dynamic>> groups = {};
    for (final a in accounts) {
      final group = (a['account_group'] ?? 'Other').toString();
      groups.putIfAbsent(group, () => []).add(a);
    }

    // Sort groups by type order
    final typeOrder = {'ASSET': 0, 'LIABILITY': 1, 'EQUITY': 2, 'REVENUE': 3, 'EXPENSE': 4};
    final sortedGroups = groups.entries.toList()
      ..sort((a, b) {
        final aType = a.value.first['account_type'] ?? '';
        final bType = b.value.first['account_type'] ?? '';
        return (typeOrder[aType] ?? 5).compareTo(typeOrder[bType] ?? 5);
      });

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
      itemCount: sortedGroups.length,
      itemBuilder: (context, i) {
        final groupName = sortedGroups[i].key;
        final groupAccounts = sortedGroups[i].value;
        final groupType = groupAccounts.first['account_type'] ?? '';
        final typeColor = _typeColor(groupType);

        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.06),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        groupType,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: typeColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        groupName,
                        style: AppTextStyles.h3.copyWith(fontSize: 14),
                      ),
                    ),
                    Text(
                      '${groupAccounts.length}',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              // Account items
              ...groupAccounts.map((a) => _buildAccountTile(a, isMobile)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListView(List<dynamic> accounts, bool isMobile) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
      itemCount: accounts.length,
      itemBuilder: (context, i) {
        return _buildAccountTile(accounts[i], isMobile);
      },
    );
  }

  Widget _buildAccountTile(dynamic a, bool isMobile) {
    final balance = double.tryParse((a['current_balance'] ?? 0).toString()) ?? 0.0;
    final type = a['account_type'] ?? '';
    final typeColor = _typeColor(type);

    return InkWell(
      onTap: () {
        // Navigate to ledger for this account
        final provider = context.read<AccountingProvider>();
        provider.fetchLedgerStatement(a['id'].toString());
        // Could navigate to a detail view
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderLight)),
        ),
        child: Row(
          children: [
            // Account code badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                a['code'] ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: typeColor),
              ),
            ),
            const SizedBox(width: 12),
            // Name and group
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a['name'] ?? 'Account',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (a['account_group'] != null)
                    Text(
                      a['account_group'],
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                ],
              ),
            ),
            // Balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${balance.toStringAsFixed(2)}',
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: balance != 0 ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                ),
                if (!a['is_active'])
                  Text('Inactive', style: AppTextStyles.caption.copyWith(color: AppColors.error, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'ASSET':
        return AppColors.brandNavy;
      case 'LIABILITY':
        return AppColors.error;
      case 'EQUITY':
        return AppColors.info;
      case 'REVENUE':
        return AppColors.success;
      case 'EXPENSE':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }
}
