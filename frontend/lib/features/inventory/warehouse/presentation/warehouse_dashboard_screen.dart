/// Warehouse dashboard — KPI cards, warehouse list with quick counts,
/// recent transfers and adjustments.
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
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';
import 'package:apexbooks/features/inventory/stock/presentation/inventory_list_screen.dart';
import 'package:apexbooks/features/inventory/transfers/services/transfer_service.dart';
import 'package:apexbooks/features/inventory/transfers/presentation/transfer_list_provider.dart';
import 'package:apexbooks/features/inventory/adjustment/services/adjustment_service.dart';
import 'package:apexbooks/features/inventory/adjustment/presentation/adjustment_list_provider.dart';
import '../services/warehouse_service.dart';
import 'warehouse_providers.dart';
import 'warehouse_detail_screen.dart';
import 'warehouse_form_screen.dart';

class WarehouseDashboardScreen extends ConsumerStatefulWidget {
  const WarehouseDashboardScreen({super.key});
  @override
  ConsumerState<WarehouseDashboardScreen> createState() =>
      _WarehouseDashboardScreenState();
}

class _WarehouseDashboardScreenState
    extends ConsumerState<WarehouseDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final whAsync = ref.watch(warehouseListProvider);
    final dashAsync = ref.watch(warehouseDashboardProvider);
    final stockAsync = ref.watch(stockBalancesProvider);
    final transferAsync = ref.watch(transferListProvider);
    final adjAsync = ref.watch(adjustmentListProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    final warehouses = whAsync.valueOrNull ?? <Warehouse>[];
    final transfers = transferAsync.valueOrNull ?? <Transfer>[];
    final adjustments = adjAsync.valueOrNull ?? <AdjustmentListItem>[];

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Warehouse Dashboard',
            subtitle: 'Multi-location inventory at a glance.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Warehouse'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const WarehouseFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(warehouseListProvider)),
              ),
            ],
          ),
          Expanded(
            child: dashAsync.when(
              loading: () => ListView(
                padding: EdgeInsets.all(isMobile ? 12 : 24),
                children: [
                  const Row(
                    children: [
                      Expanded(child: KpiCardSkeleton()),
                      SizedBox(width: 12),
                      Expanded(child: KpiCardSkeleton()),
                      SizedBox(width: 12),
                      Expanded(child: KpiCardSkeleton()),
                      SizedBox(width: 12),
                      Expanded(child: KpiCardSkeleton()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  for (int i = 0; i < 3; i++) const ListItemSkeleton(),
                ],
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(warehouseDashboardProvider),
              ),
              data: (dash) => ListView(
                padding: EdgeInsets.all(isMobile ? 12 : 24),
                children: [
                  // ── KPI Row ──
                  _kpiRow(dash, colors, fmt, isMobile),
                  const SizedBox(height: 24),

                  // ── Warehouse list ──
                  _SectionHeader(
                    label: 'Warehouses',
                    colors: colors,
                    onViewAll: warehouses.length > 5
                        ? () {
                            // Switch to warehouses tab if available
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _warehouseGrid(warehouses, stockAsync, colors, fmt, isMobile),
                  const SizedBox(height: 24),

                  // ── Recent Transfers ──
                  _SectionHeader(label: 'Recent Transfers', colors: colors),
                  const SizedBox(height: 8),
                  _recentTransfers(transfers, colors, fmt),
                  const SizedBox(height: 24),

                  // ── Recent Adjustments ──
                  _SectionHeader(label: 'Recent Adjustments', colors: colors),
                  const SizedBox(height: 8),
                  _recentAdjustments(adjustments, colors),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiRow(
    WarehouseDashboardData dash,
    ApexColors c,
    NumberFormatter fmt,
    bool isMobile,
  ) {
    final kpis = [
      _KpiData(
        icon: Icons.warehouse_outlined,
        label: 'Warehouses',
        value: '${dash.totalWarehouses}',
        color: c.info,
      ),
      _KpiData(
        icon: Icons.inventory_2_outlined,
        label: 'Products in Stock',
        value: '${dash.totalProducts}',
        color: c.primary,
      ),
      _KpiData(
        icon: Icons.currency_rupee_rounded,
        label: 'Stock Value',
        value: fmt.currency(dash.totalStockValue),
        color: c.success,
      ),
      _KpiData(
        icon: Icons.warning_amber_rounded,
        label: 'Low Stock',
        value: '${dash.lowStockCount}',
        color: dash.lowStockCount > 0 ? c.warning : c.textMuted,
      ),
    ];

    return Column(
      children: [
        if (isMobile)
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: _kpiCard(kpis[0], c)),
                  const SizedBox(width: 12),
                  Expanded(child: _kpiCard(kpis[1], c)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _kpiCard(kpis[2], c)),
                  const SizedBox(width: 12),
                  Expanded(child: _kpiCard(kpis[3], c)),
                ],
              ),
            ],
          )
        else
          Row(
            children: kpis
                .map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Expanded(child: _kpiCard(k, c)),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _kpiCard(_KpiData kpi, ApexColors c) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kpi.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(ApexRadius.sm),
            ),
            child: Icon(kpi.icon, size: 18, color: kpi.color),
          ),
          const SizedBox(height: 14),
          Text(
            kpi.value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(kpi.label, style: TextStyle(fontSize: 12, color: c.textMuted)),
        ],
      ),
    );
  }

  Widget _warehouseGrid(
    List<Warehouse> warehouses,
    AsyncValue<List<StockBalance>> stockAsync,
    ApexColors c,
    NumberFormatter fmt,
    bool isMobile,
  ) {
    final stock = stockAsync.valueOrNull ?? <StockBalance>[];
    final stockByWarehouse = <String?, List<StockBalance>>{};
    for (final s in stock) {
      stockByWarehouse.putIfAbsent(s.warehouseId, () => []).add(s);
    }

    if (warehouses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.warehouse_outlined, size: 40, color: c.textMuted),
              const SizedBox(height: 12),
              Text(
                'No warehouses yet',
                style: TextStyle(color: c.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const WarehouseFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(warehouseListProvider)),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Warehouse'),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isMobile ? 3.2 : 1.8,
      ),
      itemCount: warehouses.length,
      itemBuilder: (_, i) {
        final w = warehouses[i];
        final whStock = stockByWarehouse[w.id] ?? <StockBalance>[];
        final productCount = whStock.length;
        final stockValue = whStock.fold<double>(0, (a, b) => a + b.stockValue);
        final lowCount = whStock.where((s) => s.isLowStock).length;

        return InkWell(
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WarehouseDetailScreen(warehouseId: w.id),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(ApexRadius.lg),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    StatusBadge(
                      label: w.isActive ? 'ACTIVE' : 'INACTIVE',
                      tone: w.isActive
                          ? StatusTone.success
                          : StatusTone.neutral,
                    ),
                  ],
                ),
                if (w.code.isNotEmpty)
                  Text(
                    w.code,
                    style: TextStyle(fontSize: 11, color: c.textMuted),
                  ),
                const Spacer(),
                Row(
                  children: [
                    _statChip(
                      Icons.inventory_2_outlined,
                      '$productCount products',
                      c,
                    ),
                    if (lowCount > 0) ...[
                      const SizedBox(width: 8),
                      _statChip(
                        Icons.warning_amber_rounded,
                        '$lowCount low',
                        c,
                        color: c.warning,
                      ),
                    ],
                    const Spacer(),
                    Text(
                      fmt.currency(stockValue),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
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

  Widget _statChip(IconData icon, String text, ApexColors c, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? c.textMuted),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color ?? c.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _recentTransfers(
    List<Transfer> transfers,
    ApexColors c,
    NumberFormatter fmt,
  ) {
    final recent = transfers.take(5).toList();
    if (recent.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Center(
          child: Text(
            'No transfers yet',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: recent.map((t) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 16,
                  color: c.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.transferNumber.isNotEmpty
                            ? t.transferNumber
                            : 'Transfer',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        '${t.fromWarehouseName} → ${t.toWarehouseName}',
                        style: TextStyle(fontSize: 11.5, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
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
          );
        }).toList(),
      ),
    );
  }

  Widget _recentAdjustments(
    List<AdjustmentListItem> adjustments,
    ApexColors c,
  ) {
    final recent = adjustments.take(5).toList();
    if (recent.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Center(
          child: Text(
            'No adjustments yet',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: recent.map((a) {
          final tone = switch (a.status) {
            'CONFIRMED' => StatusTone.success,
            'CANCELLED' => StatusTone.danger,
            _ => StatusTone.neutral,
          };
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 16, color: c.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.adjustmentNumber.isNotEmpty
                        ? a.adjustmentNumber
                        : 'Adjustment',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                StatusBadge(label: a.status, tone: tone),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.colors,
    this.onViewAll,
  });

  final String label;
  final ApexColors colors;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: colors.textMuted,
          ),
        ),
        const Spacer(),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: const Text('View all', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
