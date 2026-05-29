import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/inventory_adjustments/inventory_adjustment_form_view.dart';

class InventoryAdjustmentDetailView extends StatefulWidget {
  final String adjustmentId;

  const InventoryAdjustmentDetailView({super.key, required this.adjustmentId});

  @override
  State<InventoryAdjustmentDetailView> createState() => _InventoryAdjustmentDetailViewState();
}

class _InventoryAdjustmentDetailViewState extends State<InventoryAdjustmentDetailView> {
  Map<String, dynamic>? _adj;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() async {
    final detail = await context.read<InventoryAdjustmentProvider>().fetchAdjustmentDetail(widget.adjustmentId);
    if (mounted) setState(() { _adj = detail; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: LoadingState(message: 'Loading...'));
    if (_adj == null) return const Scaffold(body: ErrorState(message: 'Adjustment not found'));

    final a = _adj!;
    final status = a['status'] ?? 'DRAFT';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(a['adjustment_number'] ?? 'Adjustment Detail'),
        actions: [
          if (status == 'DRAFT')
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryAdjustmentFormView(adjustment: a))).then((_) => _fetch()), tooltip: 'Edit'),
          StatusBadge(label: status),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.inventory_2_outlined, size: 20, color: Color(0xFF1565C0))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('INVENTORY ADJUSTMENT', style: AppTextStyles.labelSmall), Text(a['adjustment_number'] ?? 'N/A', style: AppTextStyles.h2)])),
                  ]),
                  const SizedBox(height: 16),
                  const Divider(),
                  InfoRow(label: 'Type', value: a['adjustment_type'] ?? 'N/A'),
                  InfoRow(label: 'Date', value: a['adjustment_date'] ?? 'N/A'),
                  InfoRow(label: 'Reason', value: a['reason'] ?? '-'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'ADJUSTMENTS'),
                  ...((a['lines'] as List?) ?? []).map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(l['product_name'] ?? 'N/A', style: AppTextStyles.bodySmall)),
                        Text('${l['quantity']} ${l['uom'] ?? 'nos'}', style: AppTextStyles.caption),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (status == 'DRAFT')
              ActionButton(label: 'Confirm Adjustment', tier: ActionTier.warning, onPressed: () async {
                final ok = await AppConfirmDialog.show(context, title: 'Confirm?', message: 'Confirm this adjustment? It will update stock levels.');
                if (ok == true) {
                  final success = await context.read<InventoryAdjustmentProvider>().confirmAdjustment(widget.adjustmentId);
                  if (success) { _fetch(); }
                }
              }),
            if (status != 'CANCELLED' && status != 'CONFIRMED') ...[
              const SizedBox(height: 12),
              ActionButton(label: 'Cancel Adjustment', tier: ActionTier.dangerous, onPressed: () async {
                final ok = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this adjustment?');
                if (ok == true) {
                  final success = await context.read<InventoryAdjustmentProvider>().cancelAdjustment(widget.adjustmentId);
                  if (success) { _fetch(); }
                }
              }),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
