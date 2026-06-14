import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' show LoadingState, ErrorState, StatusBadge, AppConfirmDialog;
import 'package:flutter_client/views/shared/design_system.dart';
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
    final lines = (a['lines'] is List ? a['lines'] as List : []);

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
                  AppInfoRow(label: 'Type', value: a['adjustment_type'] ?? 'N/A'),
                  AppInfoRow(label: 'Date', value: AppDate.format(a['adjustment_date'])),
                  AppInfoRow(label: 'Reason', value: a['reason'] ?? '-'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: AppSection(
                title: 'ADJUSTMENTS',
                child: lines.isEmpty
                  ? Text('No adjustments', style: TextStyle(color: AppColors.textMuted))
                  : AppDataTable(
                      columns: const ['Product', 'Quantity'],
                      rows: lines.map((l) => [
                        Text(l['product_name'] ?? 'N/A', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        Text('${l['quantity']} ${l['uom'] ?? 'nos'}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ]).toList(),
                    ),
              ),
            ),
            const SizedBox(height: 24),
            if (status == 'DRAFT')
              AppButton(
                label: 'Confirm Adjustment',
                icon: Icons.warning_amber_outlined,
                isPrimary: true,
                color: AppColors.actionWarning,
                onTap: () async {
                  final ok = await AppConfirmDialog.show(context, title: 'Confirm?', message: 'Confirm this adjustment? It will update stock levels.');
                  if (ok == true) {
                    final success = await context.read<InventoryAdjustmentProvider>().confirmAdjustment(widget.adjustmentId);
                    if (success) { _fetch(); }
                  }
                },
              ),
            if (status != 'CANCELLED' && status != 'CONFIRMED') ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Cancel Adjustment',
                icon: Icons.delete_outline_rounded,
                isPrimary: true,
                color: AppColors.actionDangerous,
                textColor: AppColors.textWhite,
                onTap: () async {
                  final ok = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this adjustment?');
                  if (ok == true) {
                    final success = await context.read<InventoryAdjustmentProvider>().cancelAdjustment(widget.adjustmentId);
                    if (success) { _fetch(); }
                  }
                },
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
