import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
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
    this.onEdit,
    this.onPrint,
    this.onShare,
    this.onAction,
  });

  final List<InvoiceListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(InvoiceListItem) onSelect;
  final NumberFormatter fmt;
  final ApexColors colors;
  final void Function(InvoiceListItem)? onEdit;
  final void Function(InvoiceListItem)? onPrint;
  final void Function(InvoiceListItem)? onShare;
  final void Function(InvoiceListItem, String)? onAction;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobileInvoiceList(
        items: items,
        selectedId: selectedId,
        onSelect: onSelect,
        fmt: fmt,
        colors: colors,
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth.clamp(1150.0, double.infinity);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: tableWidth,
              minHeight: constraints.maxHeight,
              maxHeight: constraints.maxHeight,
            ),
            child: Column(
              children: [
                // Header row with filter funnel icons
                Container(
                  color: colors.surfaceMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      _sortableHeader(context, 'Date', 'issueDate', 120),
                      _sortableHeader(context, 'Invoice no', 'invoiceNumber', 150),
                      _sortableHeader(context, 'Party Name', 'contactName', 250),
                      _sortableHeader(context, 'Transaction', 'transaction', 110),
                      _sortableHeader(context, 'Payment Type', 'status', 140),
                      _sortableHeader(
                        context,
                        'Amount',
                        'total',
                        130,
                        alignRight: true,
                      ),
                      _sortableHeader(
                        context,
                        'Balance',
                        'outstanding',
                        130,
                        alignRight: true,
                      ),
                      const SizedBox(
                        width: 120,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Actions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
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
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.border),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final isSelected = item.id == selectedId;
                      return InkWell(
                        onTap: () => (onEdit ?? onSelect)(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: isSelected ? colors.primaryContainer : null,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  item.issueDate,
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              SizedBox(
                                width: 150,
                                child: Text(
                                  item.invoiceNumber,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 250,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Text(
                                    item.contactName,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 110,
                                child: Text(
                                  'Sale',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: Text(
                                  item.status == InvoiceStatus.paid
                                      ? 'DCB BANK'
                                      : item.status.value.replaceAll('_', ' '),
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    fmt.currency(item.total),
                                    textAlign: TextAlign.right,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    fmt.currency(item.outstanding),
                                    textAlign: TextAlign.right,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: item.outstanding > 0 ? colors.danger : null,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.print_outlined, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      tooltip: 'Print Invoice',
                                      onPressed: () => (onPrint ?? onSelect)(item),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      tooltip: 'Share Invoice',
                                      onPressed: () => (onShare ?? onSelect)(item),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert_rounded, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      tooltip: 'More Options',
                                      onSelected: (action) {
                                        if (onAction != null) {
                                          onAction!(item, action);
                                        } else if (action == 'view_edit') {
                                          (onEdit ?? onSelect)(item);
                                        } else if (action == 'print') {
                                          (onPrint ?? onSelect)(item);
                                        } else if (action == 'share') {
                                          (onShare ?? onSelect)(item);
                                        } else {
                                          onSelect(item);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'view_edit', child: Text('View/Edit')),
                                        PopupMenuItem(value: 'einvoice', child: Text('Generate e-Invoice')),
                                        PopupMenuItem(value: 'return', child: Text('Convert To Return')),
                                        PopupMenuItem(value: 'challan', child: Text('Preview Delivery Challan')),
                                        PopupMenuItem(value: 'cancel', child: Text('Cancel Invoice')),
                                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                                        PopupMenuItem(value: 'open_pdf', child: Text('Open PDF')),
                                        PopupMenuItem(value: 'preview', child: Text('Preview')),
                                        PopupMenuItem(value: 'print', child: Text('Print')),
                                        PopupMenuItem(value: 'history', child: Text('View History')),
                                      ],
                                    ),
                                  ],
                                ),
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
      },
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
                  color: isSorted ? colors.primary : colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.filter_list_rounded,
              size: 13,
              color: colors.textMuted,
            ),
            if (isSorted) ...[
              const SizedBox(width: 2),
              Icon(
                asc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: colors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobileInvoiceList extends StatelessWidget {
  const _MobileInvoiceList({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.fmt,
    required this.colors,
  });

  final List<InvoiceListItem> items;
  final String? selectedId;
  final void Function(InvoiceListItem) onSelect;
  final NumberFormatter fmt;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    itemCount: items.length,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      final item = items[index];
      final overdue =
          item.outstanding > 0 &&
          DateTime.tryParse(item.dueDate)?.isBefore(DateTime.now()) == true;
      return Card(
        margin: EdgeInsets.zero,
        color: item.id == selectedId ? colors.primaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(ApexRadius_lg),
          onTap: () => onSelect(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.invoiceNumber,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      fmt.currency(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.contactName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                    StatusBadge(
                      label: item.status.value.replaceAll('_', ' '),
                      tone: overdue
                          ? StatusTone.warning
                          : toneForStatus(item.status.value),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 15,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      overdue
                          ? 'Overdue ${item.dueDate}'
                          : 'Due ${item.dueDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: overdue ? colors.warning : colors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    if (item.outstanding > 0)
                      Text(
                        '${fmt.currency(item.outstanding)} due',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.danger,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
