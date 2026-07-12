/// Bank reconciliation list screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/reconciliation_service.dart';
import '../models/reconciliation_models.dart';

final reconciliationListProvider =
    FutureProvider.autoDispose<List<BankReconciliationListItem>>((ref) async {
  final res = await ref.watch(reconciliationServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception('Unexpected state'),
  };
});

class ReconciliationListScreen extends ConsumerWidget {
  const ReconciliationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(reconciliationListProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Bank Reconciliation',
            subtitle: 'Reconcile bank statements with ledger entries.',
            actions: [
              FilledButton.icon(
                onPressed: () => _showUploadDialog(context, ref),
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: const Text('Upload Statement'),
              ),
            ],
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => const Center(child: LoadingSpinner(size: 32)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(reconciliationListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.account_balance_rounded,
                    title: 'No reconciliations yet',
                    subtitle: 'Upload a bank statement to get started.',
                    actionLabel: 'Upload Statement',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(ApexSpacing.lg),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _ReconciliationCard(
                    item: items[i],
                    fmt: fmt,
                    colors: colors,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showUploadDialog(BuildContext context, WidgetRef ref) async {
    // Simple upload dialog
    final colors = apexColors(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Statement'),
        content: const Text('Upload bank statement CSV/Excel file.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
        ],
      ),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Statement upload initiated.')),
      );
    }
  }
}

class _ReconciliationCard extends StatelessWidget {
  const _ReconciliationCard({
    required this.item,
    required this.colors,
    required this.fmt,
  });

  final BankReconciliationListItem item;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ApexSpacing.sm),
      child: ApexCard(
        child: ListTile(
          title: Text(item.statementDate ?? 'Bank Statement'),
          subtitle: Text('Balance: ${fmt.currency(item.closingBalance)}'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}
