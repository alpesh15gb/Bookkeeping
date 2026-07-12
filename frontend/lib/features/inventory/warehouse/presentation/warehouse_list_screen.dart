/// Warehouse list screen — with right-panel detail inspector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/warehouse_service.dart';

final warehouseListProvider = FutureProvider.autoDispose<List<Warehouse>>((
  ref,
) async {
  final res = await ref.watch(warehouseServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

class WarehouseListScreen extends ConsumerStatefulWidget {
  const WarehouseListScreen({super.key});
  @override
  ConsumerState<WarehouseListScreen> createState() =>
      _WarehouseListScreenState();
}

class _WarehouseListScreenState extends ConsumerState<WarehouseListScreen> {
  Warehouse? _selected;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(warehouseListProvider);
    final colors = apexColors(context);

    final list = Scaffold(
      body: Column(
        children: [
          const PageHeader(
            title: 'Warehouses',
            subtitle: 'Manage stock locations and bins.',
          ),
          Expanded(
            child: async.when(
              loading: () => Column(
                children: [
                  for (int i = 0; i < 6; i++)
                    const ListItemSkeleton(),
                ],
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(warehouseListProvider),
              ),
              data: (items) {
                final q = _search.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? items
                    : items
                          .where(
                            (w) =>
                                w.name.toLowerCase().contains(q) ||
                                w.code.toLowerCase().contains(q) ||
                                (w.location ?? '').toLowerCase().contains(q),
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.warehouse_outlined,
                    title: 'No warehouses',
                    subtitle: 'Add warehouses to track stock locations.',
                  );
                }
                return Column(
                  children: [
                    _searchBar(colors),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final w = filtered[i];
                          final selected = _selected?.id == w.id;
                          return Card(
                            color: selected
                                ? colors.primaryContainer.withValues(alpha: 0.2)
                                : colors.surfaceRaised,
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
                                w.code,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                              trailing: StatusBadge(
                                label: w.isActive ? 'ACTIVE' : 'INACTIVE',
                                tone: w.isActive
                                    ? StatusTone.success
                                    : StatusTone.neutral,
                              ),
                              onTap: () => setState(() => _selected = w),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
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
          width: 320,
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
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _kv('Name', _selected!.name, colors),
                    _kv('Code', _selected!.code, colors),
                    _kv('Location', _selected!.location ?? '—', colors),
                    _kv(
                      'Status',
                      _selected!.isActive ? 'Active' : 'Inactive',
                      colors,
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

  Widget _searchBar(ApexColors colors) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
  );

  Widget _kv(String k, String v, ApexColors colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
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
    ),
  );
}
