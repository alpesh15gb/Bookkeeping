import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import '../models/invoice.dart';
import '../models/invoice_status.dart';

/// Lightweight table body with sticky header, sort, and status badges.
/// Composed directly (instead of ApexTableBody) because InvoiceListItem does
/// not extend BaseModel.
class InvoiceTableBody extends StatelessWidget {
  const InvoiceTableBody({
    super.key,
    required this.items,
    required this.sort,
    required this.onSort,
    required this.selectedId,
    required this.onSelect,
    required this.fmt,
    required this.colors,
  });

  final List<InvoiceListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(InvoiceListItem) onSelect;
  final NumberFormatter fmt;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 760,
        child: Column(
          children: [
            // Sticky header row
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _sortableHeader(context, 'Code', 'invoiceNumber', 140),
                  _sortableHeader(context, 'Customer', 'contactName', 180),
                  _sortableHeader(context, 'Date', 'issueDate', 100),
                  _sortableHeader(
                    context,
                    'Total',
                    'total',
                    120,
                    alignRight: true,
                  ),
                  const SizedBox(
                    width: 140,
                    child: Text(
                      'Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Data rows
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final isSelected = item.id == selectedId;
                  return InkWell(
                    onTap: () => onSelect(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      color: isSelected ? colors.primaryContainer : null,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              item.invoiceNumber,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: Text(
                              item.contactName,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              item.issueDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              fmt.currency(item.total),
                              textAlign: TextAlign.right,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: _statusBadge(item.status),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortableHeader(
    BuildContext context,
    String label,
    String columnId,
    double width, {
    bool alignRight = false,
  }) {
    final isSorted = sort.columnId == columnId;
    final asc = sort.direction == SortDirection.ascending;
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => onSort(columnId),
        child: Row(
          mainAxisAlignment: alignRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isSorted ? colors.primary : null,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isSorted
                  ? (asc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 14,
              color: isSorted ? colors.primary : colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(InvoiceStatus status) {
    final (Color bg, Color fg, String label) = switch (status) {
      InvoiceStatus.draft => (
        colors.warning.withValues(alpha: 0.15),
        colors.warning,
        'DRAFT',
      ),
      InvoiceStatus.posted => (
        colors.info.withValues(alpha: 0.15),
        colors.info,
        'POSTED',
      ),
      InvoiceStatus.sent => (
        colors.primary.withValues(alpha: 0.15),
        colors.primary,
        'SENT',
      ),
      InvoiceStatus.partiallyPaid => (
        colors.warning.withValues(alpha: 0.15),
        colors.warning,
        'PARTIAL',
      ),
      InvoiceStatus.paid => (
        colors.success.withValues(alpha: 0.15),
        colors.success,
        'PAID',
      ),
      InvoiceStatus.cancelled => (
        colors.danger.withValues(alpha: 0.12),
        colors.danger,
        'CANCELLED',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ApexRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
