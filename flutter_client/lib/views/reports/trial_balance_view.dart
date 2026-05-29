import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class TrialBalanceView extends StatefulWidget {
  const TrialBalanceView({super.key});

  @override
  State<TrialBalanceView> createState() => _TrialBalanceViewState();
}

class _TrialBalanceViewState extends State<TrialBalanceView> {
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
    final res = await context.read<AccountingProvider>().fetchTrialBalance();
    if (mounted) {
      if (res != null) {
        setState(() { _data = res; _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load Trial Balance'; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Trial Balance'),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Generating Trial Balance...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _fetch)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final lines = _data!['lines'] as List? ?? [];
    if (lines.isEmpty) {
      return const EmptyState(
        icon: Icons.summarize_outlined,
        title: 'Empty Trial Balance',
        subtitle: 'Post some transactions to see data',
      );
    }

    final totalOpeningDeb = double.tryParse((_data!['total_opening_debits'] ?? 0).toString()) ?? 0.0;
    final totalOpeningCred = double.tryParse((_data!['total_opening_credits'] ?? 0).toString()) ?? 0.0;
    final totalDebits = double.tryParse((_data!['total_debits'] ?? 0).toString()) ?? 0.0;
    final totalCredits = double.tryParse((_data!['total_credits'] ?? 0).toString()) ?? 0.0;
    final totalClosingDeb = double.tryParse((_data!['total_closing_debits'] ?? 0).toString()) ?? 0.0;
    final totalClosingCred = double.tryParse((_data!['total_closing_credits'] ?? 0).toString()) ?? 0.0;

    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card info
          Text('As of Date: ${DateTime.now().toString().split(" ")[0]}', style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),

          // Table
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Account Name', style: AppTextStyles.labelSmall)),
                  DataColumn(label: Text('Code', style: AppTextStyles.labelSmall)),
                  DataColumn(label: Text('Debit', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                  DataColumn(label: Text('Credit', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                ],
                rows: [
                  ...lines.map((l) {
                    final clos = double.tryParse((l['closing_balance'] ?? 0).toString()) ?? 0.0;
                    final deb = clos >= 0 ? clos : 0.0;
                    final cred = clos < 0 ? clos.abs() : 0.0;

                    return DataRow(
                      cells: [
                        DataCell(Text(l['account_name'] ?? 'N/A', style: AppTextStyles.bodyMedium)),
                        DataCell(Text(l['account_code'] ?? 'N/A', style: AppTextStyles.caption)),
                        DataCell(Text(deb > 0 ? '₹${deb.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric)),
                        DataCell(Text(cred > 0 ? '₹${cred.toStringAsFixed(2)}' : '-', style: AppTextStyles.numeric)),
                      ],
                    );
                  }),
                  // Totals Row
                  DataRow(
                    selected: true,
                    cells: [
                      const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      DataCell(Text('₹${totalClosingDeb.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text('₹${totalClosingCred.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
