/// Bank reconciliation list screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../services/reconciliation_service.dart';
import '../models/reconciliation_models.dart';
import 'reconciliation_detail_screen.dart';

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
    final isMobile = ResponsiveLayout.isMobile(context);

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
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(reconciliationListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.account_balance_rounded,
                    title: 'No reconciliations yet',
                    subtitle: 'Upload a bank statement to get started.',
                    actionLabel: 'Upload Statement',
                    onAction: () => _showUploadDialog(context, ref),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.all(
                    isMobile ? ApexSpacing.md : ApexSpacing.lg,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _ReconciliationCard(
                    item: items[i],
                    fmt: fmt,
                    colors: colors,
                    onOpen: () {
                      if (items[i].id.isEmpty) return;
                      unawaited(
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => ReconciliationDetailScreen(
                                  reconciliationId: items[i].id,
                                ),
                              ),
                            )
                            .then(
                              (_) => ref.invalidate(reconciliationListProvider),
                            ),
                      );
                    },
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
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Statement'),
        content: const Text('Upload bank statement CSV/Excel file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {}
  }
}

class _ReconciliationCard extends StatelessWidget {
  const _ReconciliationCard({
    required this.item,
    required this.colors,
    required this.fmt,
    required this.onOpen,
  });

  final BankReconciliationListItem item;
  final ApexColors colors;
  final NumberFormatter fmt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ApexSpacing.sm),
      child: ApexCard(
        onTap: onOpen,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.bankingProfileName.isEmpty
                        ? 'Bank Statement'
                        : item.bankingProfileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: ApexSpacing.xs),
                  Text(
                    item.statementDate.isEmpty
                        ? 'Statement date not available'
                        : item.statementDate,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                  const SizedBox(height: ApexSpacing.sm),
                  Wrap(
                    spacing: ApexSpacing.sm,
                    runSpacing: ApexSpacing.xs,
                    children: [
                      Text(
                        'Balance: ${fmt.currency(item.closingBalance)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.difference.abs() >= 0.01)
                        Text(
                          'Diff: ${fmt.currency(item.difference)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: ApexSpacing.sm),
            StatusBadge(
              label: item.status.isEmpty ? 'OPEN' : item.status,
              tone: toneForStatus(item.status),
            ),
            const SizedBox(width: ApexSpacing.sm),
            Icon(Icons.chevron_right_rounded, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
