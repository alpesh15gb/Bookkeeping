/// Purchase Order Detail Header — Top section with PO info and actions.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/purchase_order.dart';
import '../../models/purchase_order_status.dart';

class PODetailHeader extends StatelessWidget {
  const PODetailHeader({
    super.key,
    required this.po,
    this.onClose,
    this.onEdit,
    this.onPrint,
    this.onCancel,
    this.onDelete,
    this.onCreateReceipt,
  });

  final PurchaseOrder po;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onCreateReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Title, Status, Actions
          Row(
            children: [
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  tooltip: 'Close',
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          po.poNumber,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatusBadge(status: po.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      po.contactName ?? '—',
                      style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Action Buttons
              _ActionButtonGroup(
                onEdit: onEdit,
                onPrint: onPrint,
                onCancel: onCancel,
                onDelete: onDelete,
                onCreateReceipt: onCreateReceipt,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Info Grid
          _InfoGrid(po: po),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final PurchaseOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case PurchaseOrderStatus.draft:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.edit_outlined;
        break;
      case PurchaseOrderStatus.pending:
        bgColor = colors.infoContainer;
        textColor = colors.info;
        icon = Icons.hourglass_bottom_outlined;
        break;
      case PurchaseOrderStatus.approved:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.check_circle_outline;
        break;
      case PurchaseOrderStatus.partial:
        bgColor = colors.warningContainer;
        textColor = colors.warning;
        icon = Icons.local_shipping_outlined;
        break;
      case PurchaseOrderStatus.completed:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.done_all_outlined;
        break;
      case PurchaseOrderStatus.cancelled:
        bgColor = colors.surfaceMuted;
        textColor = colors.textMuted;
        icon = Icons.cancel_outlined;
        break;
      default:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            status.name.toUpperCase(),
            style: textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtonGroup extends StatelessWidget {
  const _ActionButtonGroup({
    this.onEdit,
    this.onPrint,
    this.onCancel,
    this.onDelete,
    this.onCreateReceipt,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onCreateReceipt;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (onCreateReceipt != null)
          ApexPrimaryButton(
            icon: Icons.local_shipping_outlined,
            label: 'Create Receipt',
            onPressed: onCreateReceipt,
            size: ButtonSize.medium,
          ),
        if (onEdit != null)
          ApexSecondaryButton(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onPressed: onEdit,
            size: ButtonSize.medium,
          ),
        if (onPrint != null)
          ApexTertiaryButton(
            icon: Icons.print_outlined,
            label: 'Print',
            onPressed: onPrint,
            size: ButtonSize.medium,
          ),
        if (onCancel != null)
          ApexTertiaryButton(
            icon: Icons.cancel_outlined,
            label: 'Cancel',
            onPressed: onCancel,
            isDestructive: true,
            size: ButtonSize.medium,
          ),
        if (onDelete != null)
          ApexTertiaryButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: onDelete,
            isDestructive: true,
            size: ButtonSize.medium,
          ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.po});

  final PurchaseOrder po;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final items = <_InfoItem>[
      _InfoItem(
        label: 'Order Date',
        value: _formatDate(po.orderDate),
        icon: Icons.calendar_today,
      ),
      _InfoItem(
        label: 'Expected Date',
        value: _formatDate(po.dueDate),
        icon: Icons.event_busy,
        valueColor: po.dueDate.isNotEmpty && _isOverdue(po.dueDate, po.status)
            ? colors.error
            : null,
      ),
      if (po.posStateCode.isNotEmpty)
        _InfoItem(
          label: 'Place of Supply',
          value: po.posStateCode,
          icon: Icons.location_on_outlined,
        ),
      if (po.isPartiallyReceived)
        _InfoItem(
          label: 'Receipt Status',
          value: 'Partially Received',
          icon: Icons.local_shipping_outlined,
          valueColor: colors.warning,
        )
      else if (po.isFullyReceived)
        _InfoItem(
          label: 'Receipt Status',
          value: 'Fully Received',
          icon: Icons.done_all_outlined,
          valueColor: colors.success,
        )
      else
        _InfoItem(
          label: 'Receipt Status',
          value: 'Not Received',
          icon: Icons.local_shipping_outlined,
          valueColor: colors.textMuted,
        ),
    ];

    return Wrap(
      spacing: isMobile ? 12 : 24,
      runSpacing: 12,
      children: items.map((item) => _buildInfoCard(item, colors, textTheme)).toList(),
    );
  }

  Widget _buildInfoCard(_InfoItem item, ApexColors colors, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 18, color: colors.textSecondary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.label, style: textTheme.labelSmall?.copyWith(color: colors.textMuted)),
              Text(
                item.value,
                style: textTheme.bodyMedium?.copyWith(
                  color: item.valueColor ?? colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isOverdue(String dueDateStr, PurchaseOrderStatus status) {
    if (status == PurchaseOrderStatus.completed || status == PurchaseOrderStatus.cancelled) return false;
    try {
      final dueDate = DateTime.parse(dueDateStr);
      return dueDate.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _InfoItem {
  const _InfoItem({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
}