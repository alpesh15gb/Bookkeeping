import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../models/vendor_bill.dart';
import '../models/bill_status.dart';

/// Lightweight table body with sticky header, sort, and status badges.
///
/// Composed directly (instead of ApexTableBody) because [VendorBillListItem]
/// does not extend BaseModel — mirrors the sales `InvoiceTableBody` pattern so
/// the two transaction lists render and behave identically.
class BillTableBody extends StatelessWidget {
  const BillTableBody({
    super.key,
    required this.items,
    required this.sort,
    required this.onSort,
    required this.selectedId,
    required this.onSelect,
    required this.fmt,
    required this.colors,
  });

  final List<VendorBillListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(VendorBillListItem) onSelect;
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
                  _sortableHeader(context, 'Bill Number', 'billNumber', 160),
                  _sortableHeader(context, 'Vendor', 'contactName', 200),
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
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final isSelected = item.id == selectedId;
                  final numText = item.billNumber.isNotEmpty
                      ? item.billNumber
                      : 'Bill #${item.id.length >= 6 ? item.id.substring(0, 6) : item.id}';
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

  /// Bill-specific status label. Kept local so `core/` stays untouched while
  /// still reusing the shared [StatusBadge] visual primitive.
  String _label(BillStatus status) => switch (status) {
    BillStatus.draft => 'DRAFT',
    BillStatus.posted => 'POSTED',
    BillStatus.unpaid => 'UNPAID',
    BillStatus.partiallyPaid => 'PARTIAL',
    BillStatus.paid => 'PAID',
    BillStatus.cancelled => 'CANCELLED',
  };

  StatusTone _tone(BillStatus status) => switch (status) {
    BillStatus.draft => StatusTone.neutral,
    BillStatus.posted => StatusTone.primary,
    BillStatus.unpaid => StatusTone.warning,
    BillStatus.partiallyPaid => StatusTone.warning,
    BillStatus.paid => StatusTone.success,
    BillStatus.cancelled => StatusTone.danger,
  };
}
