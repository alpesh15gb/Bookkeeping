import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class BalanceSheetView extends StatefulWidget {
  const BalanceSheetView({super.key});

  @override
  State<BalanceSheetView> createState() => _BalanceSheetViewState();
}

class _BalanceSheetViewState extends State<BalanceSheetView> {
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
    final res = await context.read<AccountingProvider>().fetchBalanceSheet();
    if (mounted) {
      if (res != null) {
        setState(() { _data = res; _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load Balance Sheet'; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Balance Sheet'),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Generating Balance Sheet...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _fetch)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final assetsList = _data!['assets'] as List? ?? [];
    final liabilitiesList = _data!['liabilities'] as List? ?? [];
    final equityList = _data!['equity'] as List? ?? [];

    final totalAssets = double.tryParse((_data!['total_assets'] ?? 0).toString()) ?? 0.0;
    final totalLiab = double.tryParse((_data!['total_liabilities'] ?? 0).toString()) ?? 0.0;
    final totalEquity = double.tryParse((_data!['total_equity'] ?? 0).toString()) ?? 0.0;

    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        // Equation Info card
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
            child: Text(
              'Assets = Liabilities + Equity',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.brandNavy),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Assets
        _buildSection(
          title: 'ASSETS',
          items: assetsList,
          totalLabel: 'Total Assets',
          totalVal: totalAssets,
          color: const Color(0xFF067647),
        ),
        const SizedBox(height: 24),

        // Liabilities
        _buildSection(
          title: 'LIABILITIES',
          items: liabilitiesList,
          totalLabel: 'Total Liabilities',
          totalVal: totalLiab,
          color: const Color(0xFFD92D20),
        ),
        const SizedBox(height: 24),

        // Equity
        _buildSection(
          title: 'EQUITY',
          items: equityList,
          totalLabel: 'Total Equity',
          totalVal: totalEquity,
          color: const Color(0xFF175CD3),
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
                final balance = double.tryParse((item['balance'] ?? 0).toString()) ?? 0.0;
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
                      Text('₹${balance.toStringAsFixed(2)}', style: AppTextStyles.numeric),
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
