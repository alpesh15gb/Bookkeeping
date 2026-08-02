/// Purchase Order Detail Receipts — Goods receipt history with create receipt action.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import '../../models/purchase_order.dart';
import '../../models/purchase_order_status.dart';

class PODetailReceipts extends ConsumerWidget {
  const PODetailReceipts({super.key, required this.po, required this.fmt});

  final PurchaseOrder po;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);
    final isFullyReceived = po.isFullyReceived;

    return Column(
      children: [
        // Header with Create Receipt button
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Text('Goods Receipts', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!isFullyReceived && (po.status == PurchaseOrderStatus.approved || po.status == PurchaseOrderStatus.partial))
                PermissionGate(
                  permission: Permissions.goodsReceiptCreate,
                  child: ApexPrimaryButton(
                    icon: Icons.add,
                    label: 'Create Receipt',
                    onPressed: () => _openReceiptForm(context, ref),
                  ),
                ),
            ],
          ),
        ),

        // Content - receipts not yet available in model
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 24 : 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined, size: 48, color: colors.textMuted),
                  const SizedBox(height: 12),
                  Text('No Receipts Yet', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Goods receipts will appear here when created', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openReceiptForm(BuildContext context, WidgetRef ref) async {
    // TODO: Navigate to goods receipt form
    if (context.mounted) {
      ApexSnackBar.show(context: context, message: 'Receipt form not yet implemented', type: SnackBarType.info);
    }
  }
}