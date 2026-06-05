import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' show LoadingState, StatusBadge;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_form_view.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_detail_view.dart';

class InventoryAdjustmentListView extends StatefulWidget {
  const InventoryAdjustmentListView({super.key});

  @override
  State<InventoryAdjustmentListView> createState() => _InventoryAdjustmentListViewState();
}

class _InventoryAdjustmentListViewState extends State<InventoryAdjustmentListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryAdjustmentProvider>().fetchAdjustments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryAdjustmentProvider>();

    if (provider.isLoading && provider.adjustments.isEmpty) {
      return const LoadingState(message: 'Loading inventory adjustments...');
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryAdjustmentFormView())).then((_) => provider.fetchAdjustments()),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => provider.fetchAdjustments(),
        child: provider.adjustments.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  AppEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No Inventory Adjustments',
                    subtitle: 'Create adjustments to correct stock levels, write off inventory, or record stock transfers',
                  ),
                ],
              )
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: provider.adjustments.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: HeroSummaryCard(
                        title: 'Total Adjustments',
                        amount: provider.adjustments.length,
                        subtitle: '${provider.adjustments.where((a) => a['status'] == 'POSTED').length} posted',
                        icon: Icons.inventory_2_outlined,
                      ),
                    );
                  }
                  final adj = provider.adjustments[i - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: AppListTile(
                        leadingText: (adj['adjustment_number'] ?? 'A')[0].toString().toUpperCase(),
                        title: adj['adjustment_number'] ?? 'N/A',
                        subtitle: adj['reason'] ?? 'Adjustment',
                        badge: StatusBadge(label: adj['status'] ?? 'DRAFT'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryAdjustmentDetailView(adjustmentId: adj['id']))).then((_) => provider.fetchAdjustments()),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
