import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_status.dart';

/// Sticky-header, sortable table body for purchase orders.
///
/// Composed directly (not ApexTableBody) because [PurchaseOrderListItem] does
/// not extend BaseModel — mirrors the sales/vendor-bill list pattern.
class PurchaseOrderTableBody extends StatelessWidget {
  const PurchaseOrderTableBody({
    super.key,
    required this.items,
    required this.sort,
    required this.onSort,
    required this.selectedId,
    required this.onSelect,
    required this.fmt,
    required this.colors,
  });

  final List<PurchaseOrderListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(PurchaseOrderListItem) onSelect;
  final NumberFormatter fmt;
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
              minWidth: 820,
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
                  _sortableHeader(context, 'PO Number', 'poNumber', 160),
                  _sortableHeader(context, 'Vendor', 'contactName', 200),
                  _sortableHeader(context, 'Order Date', 'orderDate', 110),
                  _sortableHeader(context, 'Due Date', 'dueDate', 110),
                  _sortableHeader(
                    context,
                    'Total',
                    'total',
                    120,
                    alignRight: true,
                  ),
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
                  final numText = item.poNumber.isNotEmpty
                      ? item.poNumber
                      : 'PO #${item.id.length >= 6 ? item.id.substring(0, 6) : item.id}';
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
                            width: 160,
                            child: Text(
                              numText,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: Text(
                              item.contactName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              item.orderDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              item.dueDate,
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
                            width: 120,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                label: _label(item.status),
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

  String _label(PurchaseOrderStatus s) => switch (s) {
    PurchaseOrderStatus.draft => 'DRAFT',
    PurchaseOrderStatus.pending => 'PENDING',
    PurchaseOrderStatus.approved => 'APPROVED',
    PurchaseOrderStatus.confirmed => 'CONFIRMED',
    PurchaseOrderStatus.partial => 'PARTIAL',
    PurchaseOrderStatus.received => 'RECEIVED',
    PurchaseOrderStatus.completed => 'COMPLETED',
    PurchaseOrderStatus.cancelled => 'CANCELLED',
  };

  StatusTone _tone(PurchaseOrderStatus s) => switch (s) {
    PurchaseOrderStatus.draft => StatusTone.neutral,
    PurchaseOrderStatus.pending => StatusTone.info,
    PurchaseOrderStatus.approved => StatusTone.success,
    PurchaseOrderStatus.confirmed => StatusTone.primary,
    PurchaseOrderStatus.partial => StatusTone.warning,
    PurchaseOrderStatus.received => StatusTone.success,
    PurchaseOrderStatus.completed => StatusTone.success,
    PurchaseOrderStatus.cancelled => StatusTone.danger,
  };
}
