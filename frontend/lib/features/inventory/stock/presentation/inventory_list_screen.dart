import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/stock_models.dart';
import '../services/stock_service.dart';

final stockBalancesProvider = FutureProvider.autoDispose<List<StockBalance>>((
  ref,
) async {
  final res = await ref.watch(stockServiceProvider).getAllBalances();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key});
  @override
  ConsumerState<InventoryListScreen> createState() =>
      _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen> {
  String _search = '';
  bool _lowOnly = false;

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(stockBalancesProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Inventory Stock',
            subtitle: isMobile
                ? 'Stock levels & reorder alerts.'
                : 'Physical stock levels, valuation, and reorder alerts.',
          ),
          Expanded(
            child: asyncVals.when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(stockBalancesProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No stock balances',
                    subtitle:
                        'Stock entries are automatically created from bills and invoices.',
                  );
                }
                final q = _search.trim().toLowerCase();
                final filtered = items.where((i) {
                  if (_lowOnly && !i.isLowStock) return false;
                  if (q.isEmpty) return true;
                  return i.productName.toLowerCase().contains(q);
                }).toList();
                final lowCount = items.where((i) => i.isLowStock).length;
                final totalValue =
                    items.fold<double>(0, (a, b) => a + b.stockValue);
                return Column(
                  children: [
                    _summaryBar(
                      items.length, lowCount, totalValue, colors, fmt, isMobile,
                    ),
                    _toolbar(colors, lowCount, isMobile),
                    Expanded(
                      child: isMobile
                          ? _mobileList(filtered, colors, fmt)
                          : _desktopTable(filtered, colors, fmt),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Summary bar ────────────────────────────────────────────────
  Widget _summaryBar(
    int total,
    int low,
    double value,
    ApexColors c,
    NumberFormatter fmt,
    bool isMobile,
  ) =>
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            _summaryChip(Icons.inventory_2_outlined, '$total products', c),
            const SizedBox(width: 12),
            if (low > 0)
              _summaryChip(Icons.warning_amber_rounded, '$low low', c,
                  color: c.warning),
            const Spacer(),
            Text(
              fmt.currency(value),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      );

  Widget _summaryChip(IconData icon, String text, ApexColors c,
          {Color? color}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? c.textSecondary),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color ?? c.textSecondary)),
        ],
      );

  // ─── Toolbar ───────────────────────────────────────────────────
  Widget _toolbar(ApexColors c, int lowCount, bool isMobile) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search products…',
                  prefixIcon: Icon(Icons.search, color: c.textMuted, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isMobile ? 14 : 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ApexRadius.md),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ApexRadius.md),
                    borderSide: BorderSide(color: c.border),
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            if (lowCount > 0) ...[
              const SizedBox(width: 8),
              FilterChip(
                label: Text(
                  isMobile ? 'Low ($lowCount)' : 'Low stock ($lowCount)',
                ),
                selected: _lowOnly,
                onSelected: (v) => setState(() => _lowOnly = v),
                avatar: Icon(Icons.warning_amber_rounded,
                    size: 14, color: _lowOnly ? Colors.white : c.warning),
                selectedColor: c.warning,
                labelStyle: TextStyle(
                    fontSize: 12,
                    color: _lowOnly ? Colors.white : c.textSecondary),
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh_rounded, color: c.textSecondary),
              onPressed: () => ref.invalidate(stockBalancesProvider),
            ),
          ],
        ),
      );

  // ─── Mobile card list ──────────────────────────────────────────
  Widget _mobileList(List<StockBalance> items, ApexColors c, NumberFormatter fmt) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 40, color: c.textMuted),
              const SizedBox(height: 12),
              Text('No results', style: TextStyle(color: c.textMuted)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, a) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = items[i];
        final String statusLabel;
        final StatusTone tone;
        if (it.isOutOfStock) {
          statusLabel = 'Out of Stock';
          tone = StatusTone.danger;
        } else if (it.isLowStock) {
          statusLabel = 'Low Stock';
          tone = StatusTone.warning;
        } else {
          statusLabel = 'In Stock';
          tone = StatusTone.success;
        }

        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ApexRadius.lg),
            side: BorderSide(color: c.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(ApexSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: Product name + status badge ──
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(label: statusLabel, tone: tone),
                  ],
                ),
                if ((it.warehouseName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    it.warehouseName!,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Row 2: Stats in a 3-column grid ──
                Row(
                  children: [
                    _mobileStat(
                      label: 'Qty',
                      value: fmt.quantity(it.currentStock),
                      color: it.isLowStock ? c.warning : c.textPrimary,
                      bold: true,
                      c: c,
                    ),
                    _mobileStat(
                      label: 'Reorder',
                      value: fmt.quantity(it.reorderLevel),
                      color: c.textMuted,
                      c: c,
                    ),
                    _mobileStat(
                      label: 'Value',
                      value: fmt.currency(it.stockValue),
                      color: c.textSecondary,
                      c: c,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mobileStat({
    required String label,
    required String value,
    required Color color,
    required ApexColors c,
    bool bold = false,
  }) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );

  // ─── Desktop table ─────────────────────────────────────────────
  Widget _desktopTable(List<StockBalance> items, ApexColors c, NumberFormatter fmt) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 40, color: c.textMuted),
              const SizedBox(height: 12),
              Text('No results', style: TextStyle(color: c.textMuted)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: c.surfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(flex: 34, child: Text('Product', style: _th(c))),
              Expanded(flex: 18, child: Text('Location', style: _th(c))),
              Expanded(
                  flex: 14,
                  child: Text('Qty', style: _th(c), textAlign: TextAlign.right)),
              Expanded(
                  flex: 12,
                  child: Text('Reorder',
                      style: _th(c), textAlign: TextAlign.right)),
              Expanded(
                  flex: 14,
                  child:
                      Text('Value', style: _th(c), textAlign: TextAlign.right)),
              Expanded(flex: 12, child: Text('Status', style: _th(c))),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, a) => Divider(height: 1, color: c.border),
            itemBuilder: (_, i) {
              final it = items[i];
              final String label;
              final StatusTone tone;
              if (it.isOutOfStock) {
                label = 'Out';
                tone = StatusTone.danger;
              } else if (it.isLowStock) {
                label = 'Low';
                tone = StatusTone.warning;
              } else {
                label = 'OK';
                tone = StatusTone.success;
              }
              return Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 34,
                      child: Text(
                        it.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 18,
                      child: Text(
                        it.warehouseName ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 14,
                      child: Text(
                        fmt.quantity(it.currentStock),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: it.isLowStock ? c.warning : c.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 12,
                      child: Text(
                        fmt.quantity(it.reorderLevel),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 14,
                      child: Text(
                        fmt.currency(it.stockValue),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 12,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: StatusBadge(label: label, tone: tone),
                      ),
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

  TextStyle _th(ApexColors colors) => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: colors.textMuted,
      );
}
