/// Vendor Bill Table Body — Professional data table with sorting, selection, and hover effects.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/api/base_model.dart' show SortDirection;
import '../../models/vendor_bill.dart';
import '../../models/bill_status.dart';

class BillTableBody extends StatelessWidget {
  const BillTableBody({
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

  final List<VendorBillListItem> items;
  final ApexTableController tableCtrl;
  final NumberFormatter fmt;
  final Set<String> selectedIds;
  final String? hoveredId;
  final void Function(VendorBillListItem) onItemTap;
  final void Function(String id, bool selected) onSelectionChanged;
  final void Function(VendorBillListItem?) onHoveredChanged;

  @override
  Widget build(BuildContext context) {
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

              return _BillTableRow(
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
      ('Bill #', 160.0),
      ('Vendor', 200.0),
      ('Date', 100.0),
      ('Amount', 140.0),
      ('Paid', 140.0),
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
      case 'Bill #':
        return 'billNumber';
      case 'Vendor':
        return 'contactName';
      case 'Date':
        return 'issueDate';
      case 'Amount':
        return 'total';
      case 'Paid':
        return 'amountPaid';
      case 'Outstanding':
        return 'outstanding';
      case 'Status':
        return 'status';
      default:
        return 'billNumber';
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

class _BillTableRow extends StatefulWidget {
  const _BillTableRow({
    required this.item,
    required this.index,
    required this.fmt,
    required this.isSelected,
    required this.isHovered,
    required this.onTap,
    required this.onSelectionChanged,
    required this.onHovered,
  });

  final VendorBillListItem item;
  final int index;
  final NumberFormatter fmt;
  final bool isSelected;
  final bool isHovered;
  final VoidCallback onTap;
  final ValueChanged<bool> onSelectionChanged;
  final ValueChanged<bool> onHovered;

  @override
  State<_BillTableRow> createState() => _BillTableRowState();
}

class _BillTableRowState extends State<_BillTableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;
    final outstanding = item.total - item.amountPaid;

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
                // Bill Number
                SizedBox(
                  width: 160,
                  child: Text(
                    item.billNumber,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Vendor
                SizedBox(
                  width: 200,
                  child: Text(
                    item.contactName,
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
                // Paid
                SizedBox(
                  width: 140,
                  child: Text(
                    widget.fmt.currency(item.amountPaid),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.success,
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
                    widget.fmt.currency(outstanding),
                    style: textTheme.bodyMedium?.copyWith(
                      color: outstanding > 0 ? colors.error : colors.success,
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
      case BillStatus.posted:
      case BillStatus.unpaid:
        bgColor = colors.infoContainer;
        textColor = colors.info;
        icon = Icons.hourglass_bottom_outlined;
        break;
      case BillStatus.partiallyPaid:
        bgColor = colors.warningContainer;
        textColor = colors.warning;
        icon = Icons.pending_outlined;
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