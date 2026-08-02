import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../models/goods_receipt.dart';
import '../models/goods_receipt_status.dart';

/// Sticky-header, sortable table for goods receipts.
class GoodsReceiptTableBody extends StatelessWidget {
  const GoodsReceiptTableBody({
    super.key,
    required this.items,
    required this.sort,
    required this.onSort,
    required this.selectedId,
    required this.onSelect,
    required this.colors,
  });

  final List<GoodsReceiptListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(GoodsReceiptListItem) onSelect;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 760,
              minHeight: constraints.maxHeight,
              maxHeight: constraints.maxHeight,
            ),
            child: Column(
              children: [
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _sortableHeader(context, 'GRN Number', 'receiptNumber', 180),
                  _sortableHeader(context, 'PO Number', 'poNumber', 160),
                  _sortableHeader(context, 'Vendor', 'contactName', 180),
                  _sortableHeader(context, 'Receipt Date', 'receiptDate', 120),
                  const SizedBox(
                    width: 120,
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
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final isSelected = item.id == selectedId;
                  final numText = item.receiptNumber.isNotEmpty
                      ? item.receiptNumber
                      : 'GRN #${item.id.length >= 6 ? item.id.substring(0, 6) : item.id}';
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
                            width: 180,
                            child: Text(
                              numText,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: Text(
                              item.poNumber.isEmpty ? '—' : item.poNumber,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: Text(
                              item.contactName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              item.receiptDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                label: item.status.value,
                                tone: _tone(item.status),
                              ),
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
    double width,
  ) {
    final isSorted = sort.columnId == columnId;
    final asc = sort.direction == SortDirection.ascending;
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => onSort(columnId),
        child: Row(
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

  StatusTone _tone(GoodsReceiptStatus s) => switch (s) {
    GoodsReceiptStatus.draft => StatusTone.neutral,
    GoodsReceiptStatus.pending => StatusTone.info,
    GoodsReceiptStatus.confirmed => StatusTone.success,
    GoodsReceiptStatus.cancelled => StatusTone.danger,
  };
}
