/// Stock transfer list screen — with right-panel detail inspector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../services/transfer_service.dart';
import 'transfer_list_provider.dart';
import 'transfer_detail_screen.dart';
import 'transfer_form_screen.dart';

class TransferListScreen extends ConsumerStatefulWidget {
  const TransferListScreen({super.key});
  @override
  ConsumerState<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends ConsumerState<TransferListScreen> {
  Transfer? _selected;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(transferListProvider);
    final colors = apexColors(context);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Stock Transfers',
            subtitle: 'Move stock between warehouses.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Transfer'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const TransferFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(transferListProvider)),
              ),
            ],
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(transferListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.swap_horiz_rounded,
                    title: 'No transfers yet',
                    subtitle: 'Create a stock transfer between warehouses.',
                    actionLabel: 'New Transfer',
                    onAction: null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final t = items[i];
                    final selected = _selected?.id == t.id;
                    return Card(
                      color: selected
                          ? colors.primaryContainer.withValues(alpha: 0.2)
                          : colors.surfaceRaised,
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text(
                          t.transferNumber.isNotEmpty
                              ? t.transferNumber
                              : 'Transfer',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${t.fromWarehouseName} → ${t.toWarehouseName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                        trailing: StatusBadge(
                          label: t.status,
                          tone: t.isDraft
                              ? StatusTone.neutral
                              : t.isCompleted
                              ? StatusTone.success
                              : StatusTone.info,
                        ),
                        onTap: () => setState(() => _selected = t),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );

    if (_selected == null) return list;
    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        Container(
          width: 420,
          color: colors.surfaceMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBar(
                title: Text(
                  _selected!.transferNumber.isNotEmpty
                      ? _selected!.transferNumber
                      : 'Transfer',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected = null),
                ),
              ),
              Expanded(child: TransferDetailScreen(transferId: _selected!.id)),
            ],
          ),
        ),
      ],
    );
  }
}
