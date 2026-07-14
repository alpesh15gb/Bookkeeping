import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/adjustment_service.dart';
import 'adjustment_list_provider.dart';
import 'adjustment_form_screen.dart';

class AdjustmentListScreen extends ConsumerStatefulWidget {
  const AdjustmentListScreen({super.key});
  @override
  ConsumerState<AdjustmentListScreen> createState() =>
      _AdjustmentListScreenState();
}

class _AdjustmentListScreenState extends ConsumerState<AdjustmentListScreen> {
  String? _selectedId;
  bool _operating = false;

  Future<void> _confirm(String id) async {
    setState(() => _operating = true);
    final res = await ref.read(adjustmentServiceProvider).confirm(id);
    if (!mounted) return;
    setState(() => _operating = false);
    switch (res) {
      case Success():
        ref.invalidate(adjustmentListProvider);
        ref.invalidate(adjustmentDetailProvider(id));
      case Failure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
      default:
        break;
    }
  }

  StatusTone _tone(String s) => switch (s) {
    'CONFIRMED' => StatusTone.success,
    'CANCELLED' => StatusTone.danger,
    _ => StatusTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adjustmentListProvider);
    final colors = apexColors(context);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Stock Adjustments',
            subtitle: 'Correct stock levels for counts, damage, or write-offs.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Adjustment'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const AdjustmentFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(adjustmentListProvider)),
              ),
            ],
          ),
          Expanded(
            child: async.when(
              loading: () => Column(
                children: [
                  for (int i = 0; i < 6; i++) const ListItemSkeleton(),
                ],
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(adjustmentListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.tune_rounded,
                    title: 'No stock adjustments yet',
                    subtitle:
                        'Create an adjustment to correct on-hand quantities.',
                    actionLabel: 'New Adjustment',
                    onAction: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const AdjustmentFormScreen(),
                          ),
                        )
                        .then((_) => ref.invalidate(adjustmentListProvider)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final a = items[i];
                    final selected = a.id == _selectedId;
                    return InkWell(
                      borderRadius: BorderRadius.circular(ApexRadius.md),
                      onTap: () => setState(() => _selectedId = a.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primaryContainer.withValues(alpha: 0.3)
                              : colors.surfaceRaised,
                          borderRadius: BorderRadius.circular(ApexRadius.md),
                          border: Border.all(
                            color: selected ? colors.primary : colors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.adjustmentNumber.isEmpty
                                        ? 'Adjustment'
                                        : a.adjustmentNumber,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    a.adjustmentDate,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(label: a.status, tone: _tone(a.status)),
                          ],
                        ),
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

    if (_selectedId == null) return list;
    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        SizedBox(width: 400, child: _detail(_selectedId!, colors)),
      ],
    );
  }

  Widget _detail(String id, ApexColors colors) {
    final fmt = ref.watch(numberFormatterProvider);
    final async = ref.watch(adjustmentDetailProvider(id));
    return Container(
      color: colors.surfaceMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            backgroundColor: colors.surfaceMuted,
            elevation: 0,
            title: const Text(
              'Adjustment',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selectedId = null),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: LoadingSpinner(size: 30)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(adjustmentDetailProvider(id)),
              ),
              data: (adj) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          adj.adjustmentNumber.isEmpty
                              ? 'Adjustment'
                              : adj.adjustmentNumber,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      StatusBadge(label: adj.status, tone: _tone(adj.status)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Date: ${adj.adjustmentDate}',
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
                  if ((adj.reason ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Reason: ${adj.reason}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
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
                  ...adj.lines.map(
                    (l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            l.isIncrease
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 15,
                            color: l.isIncrease
                                ? colors.success
                                : colors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.productName.isEmpty
                                  ? l.productId
                                  : l.productName,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${l.isIncrease ? '+' : ''}${fmt.quantity(l.quantityChange)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: l.isIncrease
                                  ? colors.success
                                  : colors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (adj.isDraft)
                    FilledButton.icon(
                      onPressed: _operating ? null : () => _confirm(adj.id),
                      icon: _operating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: LoadingSpinner(size: 16),
                            )
                          : const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                            ),
                      label: const Text('Confirm & Post'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
