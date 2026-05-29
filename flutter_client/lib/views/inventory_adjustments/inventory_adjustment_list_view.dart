import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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
                  EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No Inventory Adjustments',
                    subtitle: 'Create adjustments to correct stock levels, write off inventory, or record stock transfers',
                  ),
                ],
              )
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: provider.adjustments.length,
                itemBuilder: (context, i) {
                  final adj = provider.adjustments[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: AppRadius.card,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryAdjustmentDetailView(adjustmentId: adj['id']))).then((_) => provider.fetchAdjustments()),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF1565C0)),
                      ),
                      title: Text(adj['adjustment_number'] ?? 'N/A', style: AppTextStyles.h3),
                      subtitle: Text(adj['reason'] ?? 'Adjustment', style: AppTextStyles.caption),
                      trailing: StatusBadge(label: adj['status'] ?? 'DRAFT'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
