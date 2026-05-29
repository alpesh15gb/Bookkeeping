import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class LedgerView extends StatefulWidget {
  final String accountId;
  final String accountName;

  const LedgerView({super.key, required this.accountId, required this.accountName});

  @override
  State<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<LedgerView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountingProvider>().fetchLedger(widget.accountId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountingProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0.5,
        title: Text('Ledger: ${widget.accountName}', style: AppTextStyles.h3),
      ),
      body: _buildBody(provider, isMobile),
    );
  }

  Widget _buildBody(AccountingProvider provider, bool isMobile) {
    if (provider.isLoading) return const LoadingState(message: 'Loading ledger...');
    if (provider.errorMessage != null) {
      return ErrorState(
        message: provider.errorMessage!,
        onRetry: () => provider.fetchLedger(widget.accountId),
      );
    }

    final ledger = provider.currentLedger;
    if (ledger == null) {
      return const ErrorState(message: 'Ledger data unavailable');
    }

    final entries = ledger['entries'] as List? ?? [];
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.book_outlined,
        title: 'No ledger entries',
        subtitle: 'Transactions will appear here',
      );
    }

    final openingBalance = double.parse((ledger['opening_balance'] ?? 0).toString());
    final closingBalance = double.parse((ledger['closing_balance'] ?? 0).toString());

    return Column(
      children: [
        Container(
          padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
          color: AppColors.bgSurface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Opening: ₹${openingBalance.toStringAsFixed(2)}', style: AppTextStyles.numeric),
              Text('Closing: ₹${closingBalance.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              final debit = double.tryParse((e['debit'] ?? 0).toString()) ?? 0;
              final credit = double.tryParse((e['credit'] ?? 0).toString()) ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e['date'] ?? '', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text(e['description'] ?? e['narration'] ?? '', style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (debit > 0) Text('₹${debit.toStringAsFixed(2)} Dr', style: AppTextStyles.numeric) else const SizedBox(),
                        if (credit > 0) Text('₹${credit.toStringAsFixed(2)} Cr', style: AppTextStyles.numeric) else const SizedBox(),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
