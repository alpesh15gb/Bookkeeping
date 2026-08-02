/// Goods Receipt Detail Header — Top section with GRN info and actions.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/goods_receipt.dart';
import '../../models/goods_receipt_status.dart';

class GRDetailHeader extends StatelessWidget {
  const GRDetailHeader({
    super.key,
    required this.gr,
    this.onClose,
    this.onEdit,
    this.onPrint,
    this.onCancel,
    this.onDelete,
  });

  final GoodsReceipt gr;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

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
                          gr.receiptNumber,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatusBadge(status: gr.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      gr.contactName ?? '—',
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
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Info Grid
          _InfoGrid(gr: gr),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final GoodsReceiptStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case GoodsReceiptStatus.pending:
      case GoodsReceiptStatus.draft:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.edit_outlined;
        break;
      case GoodsReceiptStatus.confirmed:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.check_circle_outline;
        break;
      case GoodsReceiptStatus.cancelled:
        bgColor = colors.surfaceMuted;
        textColor = colors.textMuted;
        icon = Icons.cancel_outlined;
        break;
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
  });

  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (onEdit != null)
          ApexSecondaryButton(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onPressed: onEdit,
            
          ),
        if (onPrint != null)
          ApexTertiaryButton(
            icon: Icons.print_outlined,
            label: 'Print',
            onPressed: onPrint,
            
          ),
        if (onCancel != null)
          ApexTertiaryButton(
            icon: Icons.cancel_outlined,
            label: 'Cancel',
            onPressed: onCancel,
            isDestructive: true,
            
          ),
        if (onDelete != null)
          ApexTertiaryButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: onDelete,
            isDestructive: true,
            
          ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.gr});

  final GoodsReceipt gr;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final items = <_InfoItem>[
      _InfoItem(
        label: 'Receipt Date',
        value: _formatDate(gr.receiptDate),
        icon: Icons.calendar_today,
      ),
      if (gr.poNumber.isNotEmpty)
        _InfoItem(
          label: 'Against PO',
          value: gr.poNumber,
          icon: Icons.shopping_cart_outlined,
        ),
      if (gr.notes?.isNotEmpty == true)
        _InfoItem(
          label: 'Notes',
          value: gr.notes!,
          icon: Icons.note_outlined,
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
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
  });

  final String label;
  final String value;
  final IconData icon;
}