/// Invoice Table Body — Professional data table with sorting, selection, and hover effects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/api/base_model.dart' show SortDirection;
import '../../models/invoice.dart';
import '../../models/invoice_status.dart';

class InvoiceTableBody extends ConsumerWidget {
  const InvoiceTableBody({
    super.key,
    required this.items,
    required this.tableCtrl,
    required this.fmt,
    required this.selectedIds,
    this.hoveredId,
    required this.onItemTap,
    required this.onSelectionChanged,
    required this.onHoveredChanged,
  });

  final List<InvoiceListItem> items;
  final ApexTableController tableCtrl;
  final NumberFormatter fmt;
  final Set<String> selectedIds;
  final String? hoveredId;
  final void Function(InvoiceListItem) onItemTap;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(InvoiceListItem?) onHoveredChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // Table Header
        Container(
          color: colors.surfaceMuted,
          child: Row(
            children: [
              // Selection column
              SizedBox(
                width: 48,
                child: Checkbox(
                  value: selectedIds.length == items.length && items.isNotEmpty,
                  onChanged: (v) => _toggleAll(v ?? false),
                  tristate: selectedIds.isNotEmpty && selectedIds.length != items.length,
                ),
              ),
              // Columns
              ..._buildHeaderCells(colors, textTheme),
            ],
          ),
        ),

        // Table Rows
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = selectedIds.contains(item.id);
              final isHovered = hoveredId == item.id;

              return _InvoiceTableRow(
                item: item,
                index: index,
                fmt: fmt,
                isSelected: isSelected,
                isHovered: isHovered,
                onTap: () => onItemTap(item),
                onSelectionChanged: (selected) => onSelectionChanged(item.id, selected),
                onHovered: (hovered) => onHoveredChanged(hovered ? item : null),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHeaderCells(ApexColors colors, TextTheme textTheme) {
    const columns = [
      ('Invoice #', 160.0),
      ('Customer', 200.0),
      ('Date', 100.0),
      ('Due Date', 100.0),
      ('Amount', 140.0),
      ('Outstanding', 140.0),
      ('Status', 100.0),
    ];

    return columns.map((col) {
      final (label, width) = col;
      final sortColumn = _mapLabelToSortColumn(label);
      final isSorted = tableCtrl.value.sort.columnId == sortColumn;

      return SizedBox(
        width: width,
        child: InkWell(
          onTap: () => tableCtrl.toggleSort(sortColumn),
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isSorted) ...[
                  const SizedBox(width: 4),
                  Icon(
                    tableCtrl.value.sort.direction == SortDirection.ascending
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: colors.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  String _mapLabelToSortColumn(String label) {
    switch (label) {
      case 'Invoice #':
        return 'invoiceNumber';
      case 'Customer':
        return 'customerName';
      case 'Date':
        return 'issueDate';
      case 'Due Date':
        return 'dueDate';
      case 'Amount':
        return 'total';
      case 'Outstanding':
        return 'outstandingAmount';
      case 'Status':
        return 'status';
      default:
        return 'invoiceNumber';
    }
  }

  void _toggleAll(bool selectAll) {
    if (selectAll) {
      for (final item in items) {
        onSelectionChanged(item.id, true);
      }
    } else {
      for (final item in items) {
        onSelectionChanged(item.id, false);
      }
    }
  }
}

class _InvoiceTableRow extends StatefulWidget {
  const _InvoiceTableRow({
    required this.item,
    required this.index,
    required this.fmt,
    required this.isSelected,
    required this.isHovered,
    required this.onTap,
    required this.onSelectionChanged,
    required this.onHovered,
  });

  final InvoiceListItem item;
  final int index;
  final NumberFormatter fmt;
  final bool isSelected;
  final bool isHovered;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectionChanged;
  final ValueChanged<bool> onHovered;

  @override
  State<_InvoiceTableRow> createState() => _InvoiceTableRowState();
}

class _InvoiceTableRowState extends State<_InvoiceTableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;

    final bgColor = widget.isSelected
        ? colors.primaryContainer.withValues(alpha: 0.2)
        : (_isHovered || widget.isHovered
            ? colors.surfaceMuted.withValues(alpha: 0.5)
            : (widget.index.isEven ? colors.surface : colors.surfaceMuted.withValues(alpha: 0.3)));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: bgColor,
        child: InkWell(
          onTap: widget.onTap,
          onHover: widget.onHovered,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Selection
                SizedBox(
                  width: 48,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: (v) => widget.onSelectionChanged(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                // Invoice Number
                SizedBox(
                  width: 160,
                  child: Text(
                    item.invoiceNumber,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Customer
                SizedBox(
                  width: 200,
                  child: Text(
                    item.customerName,
                    style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Issue Date
                SizedBox(
                  width: 100,
                  child: Text(
                    _formatDate(item.issueDate),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // Due Date
                SizedBox(
                  width: 100,
                  child: Text(
                    _formatDate(item.dueDate),
                    style: textTheme.bodyMedium?.copyWith(
                      color: _isOverdue(item.dueDate, item.status) ? colors.error : colors.textSecondary,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // Amount
                SizedBox(
                  width: 140,
                  child: Text(
                    widget.fmt.currency(item.total),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                // Outstanding
                SizedBox(
                  width: 140,
                  child: Text(
                    widget.fmt.currency(item.outstandingAmount),
                    style: textTheme.bodyMedium?.copyWith(
                      color: item.outstandingAmount > 0 ? colors.error : colors.success,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                // Status
                SizedBox(
                  width: 100,
                  child: _StatusChip(status: item.status),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isOverdue(String? dueDateStr, InvoiceStatus status) {
    if (dueDateStr == null) return false;
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            status.name.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}