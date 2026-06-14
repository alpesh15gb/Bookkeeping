import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_form_view.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_detail_view.dart';

class InventoryAdjustmentListView extends StatefulWidget {
  const InventoryAdjustmentListView({super.key});

  @override
  State<InventoryAdjustmentListView> createState() => _InventoryAdjustmentListViewState();
}

class _InventoryAdjustmentListViewState extends State<InventoryAdjustmentListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryAdjustmentProvider>().fetchAdjustments();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> get _filteredAdjustments {
    final provider = context.read<InventoryAdjustmentProvider>();
    var list = provider.adjustments;
    if (_statusFilter != 'ALL') {
      list = list.where((a) => a['status'] == _statusFilter).toList();
    }
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((a) {
        final number = (a['adjustment_number'] ?? '').toString().toLowerCase();
        final reason = (a['reason'] ?? '').toString().toLowerCase();
        return number.contains(query) || reason.contains(query);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryAdjustmentProvider>();
    final all = provider.adjustments;

    final totalCount = all.length;
    final draftCount = all.where((a) => a['status'] == 'DRAFT').length;
    final postedCount = all.where((a) => a['status'] == 'POSTED').length;
    final cancelledCount = all.where((a) => a['status'] == 'CANCELLED').length;

    final items = _filteredAdjustments.map((a) {
      return DocumentItemData(
        id: a['id'].toString(),
        docNumber: a['adjustment_number'] ?? 'ADJ',
        partyName: a['reason'] ?? 'Adjustment',
        date: a['created_at']?.toString(),
        amount: 0,
        status: a['status'] ?? 'DRAFT',
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryAdjustmentFormView())).then((_) => provider.fetchAdjustments()),
        child: const Icon(Icons.add),
      ),
      body: DocumentListView(
        title: 'Inventory Adjustments',
        searchController: _searchCtrl,
        searchHint: 'Search adjustments...',
        onSearchChanged: (_) => setState(() {}),
        filterTabs: [
          FilterTab('ALL', totalCount),
          FilterTab('DRAFT', draftCount),
          FilterTab('POSTED', postedCount),
          FilterTab('CANCELLED', cancelledCount),
        ],
        activeFilter: _statusFilter,
        onFilterChanged: (tab) => setState(() => _statusFilter = tab),
        items: items,
        isLoading: provider.isLoading && all.isEmpty,
        onRefresh: () async => provider.fetchAdjustments(),
        emptyTitle: 'No Inventory Adjustments',
        emptySubtitle: 'Create adjustments to correct stock levels or record transfers',
        emptyIcon: Icons.inventory_2_outlined,
        detailBuilder: (ctx, item) => InventoryAdjustmentDetailView(adjustmentId: item.id),
        itemBuilder: (context, item, index) {
          return AppCard(
            child: AppListTile(
              leadingText: item.docNumber[0].toUpperCase(),
              title: item.docNumber,
              subtitle: item.partyName ?? '',
              badge: StatusBadge(label: item.status),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => InventoryAdjustmentDetailView(adjustmentId: item.id),
                )).then((_) => provider.fetchAdjustments());
              },
            ),
          );
        },
      ),
    );
  }
}
