import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class StatementView extends StatefulWidget {
  const StatementView({super.key});

  @override
  State<StatementView> createState() => _StatementViewState();
}

class _StatementViewState extends State<StatementView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> _accounts = [];
  Map<String, dynamic>? _tbData;
  Map<String, dynamic>? _plData;
  Map<String, dynamic>? _bsData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetch();
  }

  void _fetch() async {
    final provider = context.read<AccountingProvider>();
    await provider.fetchAccounts();
    final tb = await provider.fetchTrialBalance();
    final pl = await provider.fetchProfitLoss();
    final bs = await provider.fetchBalanceSheet();
    if (mounted) {
      setState(() {
        _accounts = provider.accountsList ?? [];
        _tbData = tb;
        _plData = pl;
        _bsData = bs;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Chart of Accounts'),
              Tab(text: 'Trial Balance'),
              Tab(text: 'Profit & Loss'),
              Tab(text: 'Balance Sheet'),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading statements...')
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAccountsTab(),
                _buildTrialBalanceTab(),
                _buildProfitLossTab(),
                _buildBalanceSheetTab(),
              ],
            ),
    );
  }

  Widget _buildAccountsTab() {
    final isMobile = AdaptiveLayout.isMobile(context);
    if (_accounts.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'No accounts found',
        subtitle: 'Chart of accounts will appear here',
      );
    }
    return ListView.separated(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: _accounts.length,
      separatorBuilder: (context, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final acc = _accounts[i];
        return AppCard(
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${acc['code']} - ${acc['name']}', style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 2),
                    Text('Type: ${acc['account_type']}', style: AppTextStyles.caption),
                  ],
                ),
              ),
              Text(
                '₹${double.parse((acc['current_balance'] ?? 0).toString()).toStringAsFixed(2)}',
                style: AppTextStyles.numeric,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrialBalanceTab() {
    if (_tbData == null) {
      return const EmptyState(
        icon: Icons.balance_outlined,
        title: 'No trial balance data',
        subtitle: 'Data will appear once transactions are recorded',
      );
    }
    final List lines = _tbData!['lines'] ?? [];
    if (lines.isEmpty) {
      return const Center(child: Text('No trial balance lines', style: AppTextStyles.bodySmall));
    }
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.borderLight),
                headingTextStyle: AppTextStyles.labelSmall,
                dataTextStyle: AppTextStyles.bodySmall,
                border: TableBorder(
                  horizontalInside: BorderSide(color: AppColors.borderLight.withOpacity(0.5)),
                ),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Account')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                ],
                rows: lines.map<DataRow>((l) {
                  final closeBal = double.parse((l['closing_balance'] ?? 0).toString());
                  final isDebit = l['account_type'] == 'ASSET' || l['account_type'] == 'EXPENSE';
                  return DataRow(cells: [
                    DataCell(Text('${l['account_code']} - ${l['account_name']}', style: AppTextStyles.bodyMedium)),
                    DataCell(_buildTypeChip(l['account_type'])),
                    DataCell(Text(isDebit ? '₹${closeBal.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric)),
                    DataCell(Text(!isDebit ? '₹${closeBal.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric)),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitLossTab() {
    if (_plData == null) {
      return const EmptyState(
        icon: Icons.trending_up_outlined,
        title: 'No profit & loss data',
        subtitle: 'Data will appear once transactions are recorded',
      );
    }
    final List rev = _plData!['revenue_lines'] ?? [];
    final List exp = _plData!['expense_lines'] ?? [];
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('Revenue', style: AppTextStyles.h3),
                  ],
                ),
                const SizedBox(height: 8),
                ...rev.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r['account_name'] ?? '', style: AppTextStyles.body),
                      Text('₹${double.parse(r['amount'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                )),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Revenue', style: AppTextStyles.bodyMedium),
                      Text('₹${double.parse(_plData!['total_revenue'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('Expenses', style: AppTextStyles.h3),
                  ],
                ),
                const SizedBox(height: 8),
                ...exp.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e['account_name'] ?? '', style: AppTextStyles.body),
                      Text('₹${double.parse(e['amount'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                )),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Expenses', style: AppTextStyles.bodyMedium),
                      Text('₹${double.parse(_plData!['total_expenses'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Net Profit', style: AppTextStyles.h2),
                Text(
                  '₹${double.parse(_plData!['net_profit'].toString()).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.info, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceSheetTab() {
    if (_bsData == null) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'No balance sheet data',
        subtitle: 'Data will appear once transactions are recorded',
      );
    }
    final List assets = _bsData!['assets'] ?? [];
    final List liabilities = _bsData!['liabilities'] ?? [];
    if (assets.isEmpty && liabilities.isEmpty) {
      return const Center(child: Text('No balance sheet data', style: AppTextStyles.bodySmall));
    }
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('Assets', style: AppTextStyles.h3),
                  ],
                ),
                const SizedBox(height: 8),
                ...assets.map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(a['account_name'] ?? '', style: AppTextStyles.body),
                      Text('₹${double.parse(a['balance'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                )),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Assets', style: AppTextStyles.bodyMedium),
                      Text('₹${double.parse(_bsData!['total_assets'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text('Liabilities & Equity', style: AppTextStyles.h3),
                  ],
                ),
                const SizedBox(height: 8),
                ...liabilities.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l['account_name'] ?? '', style: AppTextStyles.body),
                      Text('₹${double.parse(l['balance'].toString()).toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                )),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: AppTextStyles.bodyMedium),
                      Text(
                        '₹${((double.tryParse((_bsData!['total_liabilities'] ?? 0).toString()) ?? 0.0) + (double.tryParse((_bsData!['total_equity'] ?? 0).toString()) ?? 0.0)).toStringAsFixed(2)}',
                        style: AppTextStyles.numeric,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String? type) {
    final color = switch (type?.toUpperCase()) {
      'ASSET' => Colors.teal,
      'LIABILITY' => Colors.indigo,
      'EXPENSE' => Colors.red,
      'REVENUE' => Colors.green,
      'EQUITY' => Colors.blue,
      _ => AppColors.textMuted,
    };
    final bg = switch (type?.toUpperCase()) {
      'ASSET' => const Color(0xFFE0F2F1),
      'LIABILITY' => const Color(0xFFE8EAF6),
      'EXPENSE' => const Color(0xFFFFEBEE),
      'REVENUE' => const Color(0xFFE8F5E9),
      'EQUITY' => const Color(0xFFE3F2FD),
      _ => AppColors.typeDraftBg,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.badge,
      ),
      child: Text(
        type ?? '',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
