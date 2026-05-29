import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class ProfitLossView extends StatefulWidget {
  const ProfitLossView({super.key});

  @override
  State<ProfitLossView> createState() => _ProfitLossViewState();
}

class _ProfitLossViewState extends State<ProfitLossView> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() async {
    setState(() { _isLoading = true; _error = null; });
    final res = await context.read<AccountingProvider>().fetchProfitLoss();
    if (mounted) {
      if (res != null) {
        setState(() { _data = res; _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load Profit & Loss'; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Profit & Loss'),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Generating Profit & Loss statement...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _fetch)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final revenueList = _data!['revenue_lines'] as List? ?? [];
    final expenseList = _data!['expense_lines'] as List? ?? [];

    final totalRev = double.tryParse((_data!['total_revenue'] ?? 0).toString()) ?? 0.0;
    final totalExp = double.tryParse((_data!['total_expenses'] ?? 0).toString()) ?? 0.0;
    final netProfit = double.tryParse((_data!['net_profit'] ?? 0).toString()) ?? 0.0;

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        // Net Profit Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: netProfit >= 0 ? const Color(0xFFECFDF3) : const Color(0xFFFEF3F2),
            borderRadius: AppRadius.card,
            border: Border.all(
              color: netProfit >= 0 ? const Color(0xFFD0F5E0) : const Color(0xFFFECDCA),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('NET PROFIT / LOSS', style: AppTextStyles.labelSmall.copyWith(
                color: netProfit >= 0 ? const Color(0xFF067647) : const Color(0xFFB42318),
              )),
              const SizedBox(height: 8),
              Text(
                '₹${netProfit.toStringAsFixed(2)}',
                style: AppTextStyles.numericLarge.copyWith(
                  fontSize: 28,
                  color: netProfit >= 0 ? const Color(0xFF067647) : const Color(0xFFB42318),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Revenue Section
        _buildSection(
          title: 'REVENUE (INCOME)',
          items: revenueList,
          totalLabel: 'Total Revenue',
          totalVal: totalRev,
          color: const Color(0xFF067647),
        ),
        const SizedBox(height: 24),

        // Expense Section
        _buildSection(
          title: 'OPERATING EXPENSES',
          items: expenseList,
          totalLabel: 'Total Expenses',
          totalVal: totalExp,
          color: const Color(0xFFB42318),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List items,
    required String totalLabel,
    required double totalVal,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: AppTextStyles.labelSmall),
          ),
          const Divider(height: 1),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No accounts in this section', style: AppTextStyles.bodySmall)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                final amt = double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['account_name'] ?? 'N/A', style: AppTextStyles.bodyMedium),
                          if (item['account_code'] != null)
                            Text(item['account_code'], style: AppTextStyles.caption),
                        ],
                      ),
                      Text('₹${amt.toStringAsFixed(2)}', style: AppTextStyles.numeric),
                    ],
                  ),
                );
              },
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(totalLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('₹${totalVal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
