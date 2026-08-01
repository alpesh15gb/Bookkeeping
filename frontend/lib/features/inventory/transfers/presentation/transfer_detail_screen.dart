/// Transfer detail — right-panel inspector for stock transfers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../services/transfer_service.dart';
import 'transfer_list_provider.dart';

final transferDetailProvider = FutureProvider.autoDispose
    .family<Transfer, String>((ref, id) async {
      final res = await ref.watch(transferServiceProvider).get(id);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

class TransferDetailScreen extends ConsumerWidget {
  const TransferDetailScreen({super.key, required this.transferId});
  final String transferId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transferDetailProvider(transferId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return async.when(
      loading: () => const Center(child: LoadingSpinner(size: 36)),
      error: (err, _) => ErrorView(
        message: userFacingErrorMessage(err),
        onRetry: () => ref.invalidate(transferDetailProvider(transferId)),
      ),
      data: (t) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (t.isDraft) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _complete(context, ref, t),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Complete Transfer'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _cancel(context, ref, t),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _kv('Transfer No.', t.transferNumber, colors),
          const SizedBox(height: 12),
          _kv('Date', t.transferDate, colors),
          const SizedBox(height: 12),
          _kv('From', t.fromWarehouseName, colors),
          const SizedBox(height: 12),
          _kv('To', t.toWarehouseName, colors),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Status',
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
              const SizedBox(width: 12),
              StatusBadge(
                label: t.status,
                tone: t.isDraft
                    ? StatusTone.neutral
                    : t.isCompleted
                    ? StatusTone.success
                    : StatusTone.info,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'LINES',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          ...t.lines.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.productName,
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    ),
                  ),
                  Text(
                    fmt.quantity(l.quantity),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    Transfer transfer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete stock transfer?'),
        content: Text(
          'This will move stock from ${transfer.fromWarehouseName} to '
          '${transfer.toWarehouseName}. The completed transfer cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(transferServiceProvider)
        .complete(transfer.id);
    if (!context.mounted) return;
    if (result is Success<Transfer>) {
      ref.invalidate(transferDetailProvider(transfer.id));
      ref.invalidate(transferListProvider);
      ref
          .read(notificationServiceProvider)
          .success(context, 'Stock transfer completed.', title: 'Completed');
    } else {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            (result as Failure<Transfer>).error.message,
            title: 'Could not complete transfer',
          );
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    Transfer transfer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel draft transfer?'),
        content: const Text('No stock movement will be posted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref.read(transferServiceProvider).cancel(transfer.id);
    if (!context.mounted) return;
    if (result is Success<Transfer>) {
      ref.invalidate(transferDetailProvider(transfer.id));
      ref.invalidate(transferListProvider);
      ref
          .read(notificationServiceProvider)
          .info(context, 'Draft transfer cancelled.', title: 'Cancelled');
    } else {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            (result as Failure<Transfer>).error.message,
            title: 'Could not cancel transfer',
          );
    }
  }

  Widget _kv(String k, String v, ApexColors colors) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 100,
        child: Text(
          k,
          style: TextStyle(fontSize: 12.5, color: colors.textMuted),
        ),
      ),
      Expanded(
        child: Text(
          v.isEmpty ? '—' : v,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
      ),
    ],
  );
}
