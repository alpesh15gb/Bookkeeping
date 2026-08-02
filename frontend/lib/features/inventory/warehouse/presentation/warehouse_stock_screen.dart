/// Warehouse-wise stock view — lists all products with stock for a specific warehouse.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../services/warehouse_service.dart';
import 'warehouse_providers.dart';

class WarehouseStockScreen extends ConsumerStatefulWidget {
  const WarehouseStockScreen({super.key, required this.warehouseId});
  final String warehouseId;

  @override
  ConsumerState<WarehouseStockScreen> createState() =>
      _WarehouseStockScreenState();
}

class _WarehouseStockScreenState extends ConsumerState<WarehouseStockScreen> {
  String _search = '';
  bool _lowOnly = false;

  @override
  Widget build(BuildContext context) {
    final whAsync = ref.watch(warehouseDetailProvider(widget.warehouseId));
    final stockAsync = ref.watch(warehouseStockProvider(widget.warehouseId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    final warehouseName = whAsync.valueOrNull?.name ?? 'Warehouse Stock';

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: warehouseName,
            subtitle: 'Stock levels for this location.',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
                onPressed: () {
                  ref.invalidate(warehouseStockProvider(widget.warehouseId));
                  ref.invalidate(warehouseDetailProvider(widget.warehouseId));
                },
              ),
            ],
          ),
          _toolbar(colors, isMobile),
          Expanded(
            child: stockAsync.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 4),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () =>
                    ref.invalidate(warehouseStockProvider(widget.warehouseId)),
              ),
              data: (items) {
                final q = _search.trim().toLowerCase();
                final filtered = items.where((s) {
                  if (_lowOnly && !s.isLowStock) return false;
                  if (q.isEmpty) return true;
                  return s.productName.toLowerCase().contains(q) ||
                      s.sku.toLowerCase().contains(q);
                }).toList();

                final totalValue = filtered.fold<double>(
                  0,
                  (a, b) => a + b.stockValue,
                );
                final lowCount = items.where((s) => s.isLowStock).length;

                return Column(
                  children: [
                    _summaryBar(
                      items.length,
                      lowCount,
                      totalValue,
                      colors,
                      fmt,
                      isMobile,
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 40,
                                      color: colors.textMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No stock items found',
                                      style: TextStyle(
                                        color: colors.textMuted,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : isMobile
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

  Widget _summaryBar(
    int total,
    int low,
    double value,
    ApexColors c,
    NumberFormatter fmt,
    bool isMobile,
  ) => Container(
    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 10),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border(bottom: BorderSide(color: c.border)),
    ),
    child: Row(
      children: [
        Text(
          '$total products',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textSecondary,
          ),
        ),
        if (low > 0) ...[
          const SizedBox(width: 8),
          Icon(Icons.warning_amber_rounded, size: 14, color: c.warning),
          const SizedBox(width: 4),
          Text(
            '$low low',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.warning,
            ),
          ),
        ],
        const Spacer(),
        Text(
          'Total: ${fmt.currency(value)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _toolbar(ApexColors c, bool isMobile) {
    final stock = ref.watch(warehouseStockProvider(widget.warehouseId));
    final lowCount = (stock.valueOrNull ?? [])
        .where((s) => s.isLowStock)
        .length;

    return Container(
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
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search products…',
                isDense: true,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: c.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius_sm),
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
              avatar: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: _lowOnly ? c.onPrimary : c.warning,
              ),
              selectedColor: c.warning,
              labelStyle: TextStyle(
                fontSize: 12,
                color: _lowOnly ? c.onPrimary : c.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mobileList(
    List<WarehouseStockItem> items,
    ApexColors c,
    NumberFormatter fmt,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = items[i];
        final String statusLabel;
        final StatusTone tone;
        if (it.isOutOfStock) {
          statusLabel = 'Out';
          tone = StatusTone.danger;
        } else if (it.isLowStock) {
          statusLabel = 'Low';
          tone = StatusTone.warning;
        } else {
          statusLabel = 'OK';
          tone = StatusTone.success;
        }

        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ApexRadius_lg),
            side: BorderSide(color: c.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      if (it.sku.isNotEmpty)
                        Text(
                          it.sku,
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Qty: ${fmt.quantity(it.currentStock)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: it.isLowStock ? c.warning : c.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            fmt.currency(it.stockValue),
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(label: statusLabel, tone: tone),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _desktopTable(
    List<WarehouseStockItem> items,
    ApexColors c,
    NumberFormatter fmt,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius_lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: c.surfaceMuted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 34, child: Text('PRODUCT', style: _th(c))),
                Expanded(flex: 16, child: Text('SKU', style: _th(c))),
                Expanded(
                  flex: 14,
                  child: Text(
                    'STOCK',
                    textAlign: TextAlign.right,
                    style: _th(c),
                  ),
                ),
                Expanded(
                  flex: 14,
                  child: Text(
                    'REORDER',
                    textAlign: TextAlign.right,
                    style: _th(c),
                  ),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    'VALUE',
                    textAlign: TextAlign.right,
                    style: _th(c),
                  ),
                ),
                Expanded(flex: 10, child: Text('STATUS', style: _th(c))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: items.length,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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
                        flex: 16,
                        child: Text(
                          it.sku.isNotEmpty ? it.sku : '—',
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
                        flex: 14,
                        child: Text(
                          fmt.quantity(it.reorderLevel),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12.5, color: c.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 16,
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
                        flex: 10,
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
      ),
    );
  }

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
