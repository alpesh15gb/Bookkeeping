/// Vendor Bill Detail Header — Top section with bill info and actions.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/vendor_bill.dart';
import '../../models/bill_status.dart';

class BillDetailHeader extends StatelessWidget {
  const BillDetailHeader({
    super.key,
    required this.bill,
    this.onClose,
    this.onEdit,
    this.onPrint,
    this.onCancel,
    this.onDelete,
    this.onRecordPayment,
  });

  final VendorBill bill;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onRecordPayment;

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
                          bill.billNumber,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatusBadge(status: bill.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bill.contactName ?? '',
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
                onRecordPayment: onRecordPayment,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Info Grid
          _InfoGrid(bill: bill),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BillStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case BillStatus.draft:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.edit_outlined;
        break;
      case BillStatus.unpaid:
        bgColor = colors.infoContainer;
        textColor = colors.info;
        icon = Icons.hourglass_bottom_outlined;
        break;
      case BillStatus.posted:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.check_circle_outline;
        break;
      case BillStatus.paid:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.paid_outlined;
        break;
      case BillStatus.cancelled:
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
    this.onRecordPayment,
  });

  final VoidCallback? onRecordPayment;
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
        if (onRecordPayment != null)
          ApexPrimaryButton(
            icon: Icons.add_circle_outline,
            label: 'Record Payment',
            onPressed: onRecordPayment,
            
          ),
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
  const _InfoGrid({required this.bill});

  final VendorBill bill;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final items = <_InfoItem>[
      _InfoItem(
        label: 'Issue Date',
        value: _formatDate(bill.issueDate),
        icon: Icons.calendar_today,
      ),
      _InfoItem(
        label: 'Due Date',
        value: _formatDate(bill.dueDate),
        icon: Icons.event_busy,
        valueColor: bill.dueDate.isNotEmpty && _isOverdue(bill.dueDate, bill.status)
            ? colors.danger
            : null,
      ),
      if (bill.referenceNumber?.isNotEmpty == true)
        _InfoItem(
          label: 'Reference',
          value: bill.referenceNumber!,
          icon: Icons.tag,
        ),
      if (bill.posStateCode.isNotEmpty)
        _InfoItem(
          label: 'Place of Supply',
          value: bill.posStateCode,
          icon: Icons.location_on_outlined,
        ),
      if (bill.tdsAmount > 0)
        _InfoItem(
          label: 'TDS Deducted',
          value: '${bill.tdsRate.toStringAsFixed(2)}% (${bill.tdsAmount.toStringAsFixed(2)})',
          icon: Icons.percent,
          valueColor: colors.warning,
        ),
      if (!bill.itcEligible)
        _InfoItem(
          label: 'ITC Eligible',
          value: 'No',
          icon: Icons.block,
          valueColor: colors.danger,
        ),
      if (bill.isGstInclusive)
        _InfoItem(
          label: 'GST Inclusive',
          value: 'Yes',
          icon: Icons.receipt_long,
          valueColor: colors.info,
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

  bool _isOverdue(String dueDateStr, BillStatus status) {
    if (status == BillStatus.paid || status == BillStatus.cancelled) return false;
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