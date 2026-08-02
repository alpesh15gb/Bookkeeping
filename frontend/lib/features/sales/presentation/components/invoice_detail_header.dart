/// Invoice Detail Header — Top section with invoice info and actions.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import '../../models/invoice.dart';
import '../../models/invoice_status.dart';

class InvoiceDetailHeader extends StatelessWidget {
  const InvoiceDetailHeader({
    super.key,
    required this.invoice,
    this.onClose,
    this.onEdit,
    this.onPrint,
    this.onEmail,
    this.onCancel,
    this.onDelete,
    this.onRecordPayment,
  });

  final Invoice invoice;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onEmail;
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
                          invoice.invoiceNumber,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StatusBadge(status: invoice.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoice.customerName ?? '',
                      style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Action Buttons
              _ActionButtonGroup(
                onEdit: onEdit,
                onPrint: onPrint,
                onEmail: onEmail,
                onCancel: onCancel,
                onDelete: onDelete,
                onRecordPayment: onRecordPayment,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Info Grid
          _InfoGrid(invoice: invoice),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    Color bgColor;
    Color textColor;
    IconData icon;

    switch (status) {
      case InvoiceStatus.draft:
        bgColor = colors.surfaceMuted;
        textColor = colors.textSecondary;
        icon = Icons.edit_outlined;
        break;
      case InvoiceStatus.sent:
        bgColor = colors.infoContainer;
        textColor = colors.info;
        icon = Icons.send_outlined;
        break;
      case InvoiceStatus.partiallyPaid:
        bgColor = colors.warningContainer;
        textColor = colors.warning;
        icon = Icons.hourglass_bottom_outlined;
        break;
      case InvoiceStatus.paid:
        bgColor = colors.successContainer;
        textColor = colors.success;
        icon = Icons.check_circle_outline;
        break;
      case InvoiceStatus.overdue:
        bgColor = colors.errorContainer;
        textColor = colors.error;
        icon = Icons.warning_amber_outlined;
        break;
      case InvoiceStatus.cancelled:
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
    this.onEmail,
    this.onCancel,
    this.onDelete,
    this.onRecordPayment,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onPrint;
  final VoidCallback? onEmail;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onRecordPayment;

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
        if (onEmail != null)
          ApexTertiaryButton(
            icon: Icons.email_outlined,
            label: 'Email',
            onPressed: onEmail,
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
  const _InfoGrid({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final items = <_InfoItem>[
      _InfoItem(
        label: 'Issue Date',
        value: _formatDate(invoice.issueDate),
        icon: Icons.calendar_today,
      ),
      _InfoItem(
        label: 'Due Date',
        value: _formatDate(invoice.dueDate),
        icon: Icons.event_busy,
        valueColor: _isOverdue(invoice.dueDate, invoice.status)
            ? colors.error
            : null,
      ),
      if (invoice.referenceNumber?.isNotEmpty == true)
        _InfoItem(
          label: 'Reference',
          value: invoice.referenceNumber!,
          icon: Icons.tag,
        ),
      if (invoice.posStateCode.isNotEmpty)
        _InfoItem(
          label: 'Place of Supply',
          value: invoice.posStateCode,
          icon: Icons.location_on_outlined,
        ),
      if (invoice.supplyType != 'DOMESTIC')
        _InfoItem(
          label: 'Supply Type',
          value: invoice.supplyType,
          icon: Icons.swap_horiz,
        ),
      if (invoice.isRcm)
        _InfoItem(
          label: 'Reverse Charge',
          value: 'Yes (RCM)',
          icon: Icons.swap_vertical_circle,
          valueColor: colors.warning,
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

  bool _isOverdue(String dueDateStr, InvoiceStatus status) {
    if (status == InvoiceStatus.paid || status == InvoiceStatus.cancelled) return false;
    try {
      final dueDate = DateTime.parse(dueDateStr);
      return dueDate.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
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