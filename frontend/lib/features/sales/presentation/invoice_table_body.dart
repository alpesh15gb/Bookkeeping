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
    return Column(
      children: [
        // Sticky header row
        Container(
          color: colors.surfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final codeW = (w * 0.15).clamp(90, 180).toDouble();
              final nameW = (w * 0.19).clamp(110, 240).toDouble();
              final dateW = (w * 0.10).clamp(70, 110).toDouble();
              final dueW = (w * 0.10).clamp(70, 110).toDouble();
              final totalW = (w * 0.14).clamp(80, 150).toDouble();
              final outstandingW = (w * 0.14).clamp(80, 150).toDouble();
              final statusW = (w * 0.14).clamp(90, 160).toDouble();
              return Row(
                children: [
                  _sortableHeader(context, 'Code', 'invoiceNumber', codeW),
                  _sortableHeader(context, 'Customer', 'contactName', nameW),
                  _sortableHeader(context, 'Date', 'issueDate', dateW),
                  _sortableHeader(context, 'Due On', 'dueDate', dueW),
                  _sortableHeader(context, 'Total', 'total', totalW, alignRight: true),
                  _sortableHeader(context, 'Outstanding', 'outstanding', outstandingW, alignRight: true),
                  SizedBox(
                    width: statusW,
                    child: Text('Status',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Data rows
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final codeW = (w * 0.15).clamp(90, 180).toDouble();
              final nameW = (w * 0.19).clamp(110, 240).toDouble();
              final dateW = (w * 0.10).clamp(70, 110).toDouble();
              final dueW = (w * 0.10).clamp(70, 110).toDouble();
              final totalW = (w * 0.14).clamp(80, 150).toDouble();
              final outstandingW = (w * 0.14).clamp(80, 150).toDouble();
              final statusW = (w * 0.14).clamp(90, 160).toDouble();
              return ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final isSelected = item.id == selectedId;
                  final overdue = item.outstanding > 0 && DateTime.tryParse(item.dueDate)?.isBefore(DateTime.now()) == true;
                  return InkWell(
                    onTap: () => onSelect(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: isSelected ? colors.primaryContainer : null,
                      child: Row(
                        children: [
                          SizedBox(
                            width: codeW,
                            child: Text(item.invoiceNumber,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(
                            width: nameW,
                            child: Text(item.contactName, style: textTheme.bodyMedium,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: dateW,
                            child: Text(item.issueDate, style: textTheme.bodyMedium),
                          ),
                          SizedBox(
                            width: dueW,
                            child: Text(item.dueDate,
                              style: textTheme.bodyMedium?.copyWith(
                                color: overdue ? colors.danger : null,
                                fontWeight: overdue ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: totalW,
                            child: Text(fmt.currency(item.total),
                              textAlign: TextAlign.right,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(
                            width: outstandingW,
                            child: Text(fmt.currency(item.outstanding),
                              textAlign: TextAlign.right,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: item.outstanding > 0 ? colors.danger : null,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: statusW,
                            child: _statusBadge(item.status),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
    final tone = switch (status) {
      InvoiceStatus.draft => StatusTone.neutral,
      InvoiceStatus.posted || InvoiceStatus.sent => StatusTone.primary,
      InvoiceStatus.partiallyPaid => StatusTone.warning,
      InvoiceStatus.paid => StatusTone.success,
      InvoiceStatus.cancelled => StatusTone.danger,
    };
    return StatusBadge(label: status.value.replaceAll('_', ' '), tone: tone);
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
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      final item = items[index];
      final overdue =
          item.outstanding > 0 &&
          DateTime.tryParse(item.dueDate)?.isBefore(DateTime.now()) == true;
      return Card(
        margin: EdgeInsets.zero,
        color: item.id == selectedId ? colors.primaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(ApexRadius.lg),
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
