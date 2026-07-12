/// Transfer detail — right-panel inspector for stock transfers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/transfer_service.dart';

final transferDetailProvider = FutureProvider.autoDispose
    .family<Transfer, String>((ref, id) async {
      // TransferService does not expose a get(id) method, so we list and filter.
      // TODO: Add backend /transfers/:id endpoint when available.
      final res = await ref.watch(transferServiceProvider).list(limit: 200);
      final items = switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
      return items.firstWhere((t) => t.id == id);
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
        message: err.toString(),
        onRetry: () => ref.invalidate(transferDetailProvider(transferId)),
      ),
      data: (t) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
