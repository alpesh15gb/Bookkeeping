/// Warehouse list screen — with right-panel detail inspector.
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
import '../services/warehouse_service.dart';
import 'warehouse_providers.dart';
import 'warehouse_form_screen.dart';
import 'warehouse_detail_screen.dart';

class WarehouseListScreen extends ConsumerStatefulWidget {
  const WarehouseListScreen({super.key});
  @override
  ConsumerState<WarehouseListScreen> createState() =>
      _WarehouseListScreenState();
}

class _WarehouseListScreenState extends ConsumerState<WarehouseListScreen> {
  Warehouse? _selected;
  String _search = '';
  String _statusFilter = 'all'; // all, active, inactive

  @override
  Widget build(BuildContext context) {
    final asyncVals = ref.watch(warehouseListProvider);
    final stockAsync = ref.watch(stockBalancesProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    // Compute stock value per warehouse (if warehouseId is populated).
    final stockByWarehouse = <String?, List<StockBalance>>{};
    final stock = stockAsync.valueOrNull ?? <StockBalance>[];
    for (final s in stock) {
      stockByWarehouse.putIfAbsent(s.warehouseId, () => []).add(s);
    }

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Warehouses',
            subtitle: 'Manage stock locations and bins.',
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
          _toolbar(colors, isMobile),
          Expanded(
            child: asyncVals.when(
              loading: () => Column(
                children: [
                  for (int i = 0; i < 6; i++) const ListItemSkeleton(),
                ],
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(warehouseListProvider),
              ),
              data: (items) {
                final q = _search.trim().toLowerCase();
                final filtered = items.where((w) {
                  if (_statusFilter == 'active' && !w.isActive) return false;
                  if (_statusFilter == 'inactive' && w.isActive) return false;
                  if (q.isEmpty) return true;
                  return w.name.toLowerCase().contains(q) ||
                      w.code.toLowerCase().contains(q) ||
                      (w.location ?? '').toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.warehouse_outlined,
                    title: 'No warehouses',
                    subtitle: 'Add warehouses to track stock locations.',
                    actionLabel: 'New Warehouse',
                    onAction: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const WarehouseFormScreen(),
                          ),
                        )
                        .then((_) => ref.invalidate(warehouseListProvider)),
                  );
                }

                return isMobile
                    ? _mobileList(filtered, stockByWarehouse, colors)
                    : _desktopTable(filtered, stockByWarehouse, colors, fmt);
              },
            ),
          ),
        ],
      ),
    );

    if (_selected == null || isMobile) return list;
    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        Container(
          width: 380,
          color: colors.surfaceMuted,
          child: Column(
            children: [
              AppBar(
                title: Text(
                  _selected!.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected = null),
                ),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Full view'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WarehouseDetailScreen(warehouseId: _selected!.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _kv('Name', _selected!.name, colors),
                    _kv('Code', _selected!.code, colors),
                    _kv('Location', _selected!.location ?? '—', colors),
                    _kv('GSTIN', _selected!.gstin ?? '—', colors),
                    _kv(
                      'Address',
                      _selected!.address?.formatted ?? '—',
                      colors,
                    ),
                    _kv(
                      'Status',
                      _selected!.isActive ? 'Active' : 'Inactive',
                      colors,
                    ),
                    _kv(
                      'Created',
                      _selected!.createdAt != null &&
                              _selected!.createdAt!.length >= 10
                          ? _selected!.createdAt!.substring(0, 10)
                          : '—',
                      colors,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WarehouseDetailScreen(
                              warehouseId: _selected!.id,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View Details'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ApexColors colors, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search warehouses…',
                isDense: true,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(width: 12),
          _statusDropdown(colors),
        ],
      ),
    );
  }

  Widget _statusDropdown(ApexColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.sm),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _statusFilter,
          isDense: true,
          borderRadius: BorderRadius.circular(ApexRadius.md),
          items: const [
            DropdownMenuItem(
              value: 'all',
              child: Text('All', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: 'active',
              child: Text('Active', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: 'inactive',
              child: Text('Inactive', style: TextStyle(fontSize: 13)),
            ),
          ],
          onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
        ),
      ),
    );
  }

  Widget _mobileList(
    List<Warehouse> items,
    Map<String?, List<StockBalance>> stockByWarehouse,
    ApexColors colors,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final w = items[i];
        final whStock = stockByWarehouse[w.id] ?? <StockBalance>[];
        return Card(
          color: colors.surfaceRaised,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text(
              w.name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              '${w.code}  ·  ${whStock.length} products',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            trailing: StatusBadge(
              label: w.isActive ? 'ACTIVE' : 'INACTIVE',
              tone: w.isActive ? StatusTone.success : StatusTone.neutral,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WarehouseDetailScreen(warehouseId: w.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _desktopTable(
    List<Warehouse> items,
    Map<String?, List<StockBalance>> stockByWarehouse,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final scrollCtrl = ScrollController();
    return Scrollbar(
      controller: scrollCtrl,
      child: ListView.builder(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final w = items[i];
          final whStock = stockByWarehouse[w.id] ?? <StockBalance>[];
          final stockValue = whStock.fold<double>(
            0,
            (a, b) => a + b.stockValue,
          );
          final productCount = whStock.length;
          final selected = _selected?.id == w.id;

          return Card(
            color: selected
                ? colors.primaryContainer.withValues(alpha: 0.2)
                : colors.surfaceRaised,
            margin: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(ApexRadius.md),
              onTap: () {
                setState(() => _selected = w);
                if (ResponsiveLayout.isMobile(context)) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WarehouseDetailScreen(warehouseId: w.id),
                    ),
                  );
                }
              },
              onDoubleTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WarehouseDetailScreen(warehouseId: w.id),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 30,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w.name,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            w.code,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 20,
                      child: Text(
                        w.location ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 14,
                      child: Text(
                        '$productCount',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 18,
                      child: Text(
                        fmt.currency(stockValue),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 14,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: StatusBadge(
                          label: w.isActive ? 'ACTIVE' : 'INACTIVE',
                          tone: w.isActive
                              ? StatusTone.success
                              : StatusTone.neutral,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v, ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
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
