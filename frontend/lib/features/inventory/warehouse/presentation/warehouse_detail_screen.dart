/// Warehouse detail screen — full-page view of a single warehouse.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/features/inventory/stock/models/stock_models.dart';
import '../services/warehouse_service.dart';
import 'warehouse_providers.dart';
import 'warehouse_form_screen.dart';
import 'warehouse_stock_screen.dart';

class WarehouseDetailScreen extends ConsumerWidget {
  const WarehouseDetailScreen({super.key, required this.warehouseId});
  final String warehouseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whAsync = ref.watch(warehouseDetailProvider(warehouseId));
    final stockAsync = ref.watch(warehouseStockProvider(warehouseId));
    final movementsAsync = ref.watch(warehouseMovementsProvider(warehouseId));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 12),
        child: _DetailAppBar(
          title: '',
          warehouseId: warehouseId,
          colors: colors,
        ),
      ),
      body: whAsync.when(
        loading: () => _buildLoading(colors),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(warehouseDetailProvider(warehouseId)),
        ),
        data: (warehouse) => _DetailContent(
          warehouse: warehouse,
          stockAsync: stockAsync,
          movementsAsync: movementsAsync,
          colors: colors,
          fmt: fmt,
          isMobile: isMobile,
        ),
      ),
    );
  }

  Widget _buildLoading(ApexColors colors) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const DetailSectionSkeleton(),
        const SizedBox(height: 16),
        const DetailSectionSkeleton(),
        const SizedBox(height: 16),
        const DetailSectionSkeleton(),
      ],
    );
  }
}

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({
    required this.title,
    required this.warehouseId,
    required this.colors,
  });

  final String title;
  final String warehouseId;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Tooltip(
                message: 'Go back',
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.textPrimary,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Warehouse',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: colors.textSecondary,
                ),
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WarehouseDetailScreen(warehouseId: warehouseId),
                        ),
                      )
                      .then((_) {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.warehouse,
    required this.stockAsync,
    required this.movementsAsync,
    required this.colors,
    required this.fmt,
    required this.isMobile,
  });

  final Warehouse warehouse;
  final AsyncValue<List<WarehouseStockItem>> stockAsync;
  final AsyncValue<List<StockMovement>> movementsAsync;
  final ApexColors colors;
  final NumberFormatter fmt;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final stockItems = stockAsync.valueOrNull ?? <WarehouseStockItem>[];

    final totalProducts = stockItems.length;
    final totalStockValue = stockItems.fold<double>(
      0,
      (a, b) => a + b.stockValue,
    );
    final lowStockCount = stockItems.where((s) => s.isLowStock).length;

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      children: [
        // ── Header card ──
        _HeaderCard(warehouse: warehouse, colors: colors, fmt: fmt),
        const SizedBox(height: 16),

        // ── KPI summary cards ──
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                icon: Icons.inventory_2_outlined,
                label: 'Products',
                value: '$totalProducts',
                color: colors.info,
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                icon: Icons.currency_rupee_rounded,
                label: 'Stock Value',
                value: fmt.currency(totalStockValue),
                color: colors.success,
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                icon: Icons.warning_amber_rounded,
                label: 'Low Stock',
                value: '$lowStockCount',
                color: lowStockCount > 0 ? colors.warning : colors.textMuted,
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Info card ──
        _InfoCard(warehouse: warehouse, colors: colors),
        const SizedBox(height: 16),

        // ── Action buttons ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WarehouseFormScreen(warehouse: warehouse),
                        ),
                      )
                      .then((_) {});
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          WarehouseStockScreen(warehouseId: warehouse.id),
                    ),
                  );
                },
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('View Stock'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Recent movements section ──
        _SectionHeader(label: 'Recent Stock Movements', colors: colors),
        const SizedBox(height: 8),
        movementsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: LoadingSpinner(size: 24),
            ),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Could not load movements.',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
          data: (m) {
            if (m.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No stock movements recorded for this warehouse.',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
              );
            }
            return _MovementsList(
              movements: m.take(10).toList(),
              colors: colors,
              fmt: fmt,
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.warehouse,
    required this.colors,
    required this.fmt,
  });

  final Warehouse warehouse;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      warehouse.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (warehouse.code.isNotEmpty)
                      Text(
                        warehouse.code,
                        style: TextStyle(fontSize: 13, color: colors.textMuted),
                      ),
                  ],
                ),
              ),
              StatusBadge(
                label: warehouse.isActive ? 'ACTIVE' : 'INACTIVE',
                tone: warehouse.isActive
                    ? StatusTone.success
                    : StatusTone.neutral,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.warehouse, required this.colors});
  final Warehouse warehouse;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DETAILS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          _kv('GSTIN', warehouse.gstin ?? '—', colors),
          _kv('Location', warehouse.location ?? '—', colors),
          _kv('Address', warehouse.address?.formatted ?? '—', colors),
          _kv(
            'Created',
            warehouse.createdAt != null && warehouse.createdAt!.length >= 10
                ? warehouse.createdAt!.substring(0, 10)
                : '—',
            colors,
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
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
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.colors});
  final String label;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: colors.textMuted,
      ),
    );
  }
}

class _MovementsList extends StatelessWidget {
  const _MovementsList({
    required this.movements,
    required this.colors,
    required this.fmt,
  });

  final List<StockMovement> movements;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 14, child: Text('DATE', style: _th(colors))),
                Expanded(flex: 34, child: Text('PRODUCT', style: _th(colors))),
                Expanded(flex: 16, child: Text('TYPE', style: _th(colors))),
                Expanded(
                  flex: 12,
                  child: Text(
                    'QTY',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          ...movements.map(
            (m) => Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 14,
                    child: Text(
                      m.createdAt != null && m.createdAt!.length >= 10
                          ? m.createdAt!.substring(0, 10)
                          : '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 34,
                    child: Text(
                      m.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 16,
                    child: StatusBadge(
                      label: m.referenceType.value,
                      tone: StatusTone.neutral,
                    ),
                  ),
                  Expanded(
                    flex: 12,
                    child: Text(
                      '${m.quantity >= 0 ? '+' : ''}${fmt.quantity(m.quantity)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: m.quantity >= 0 ? colors.success : colors.danger,
                      ),
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

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
