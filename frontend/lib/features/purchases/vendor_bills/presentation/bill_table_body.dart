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
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobileBillList(
        items: items,
        sort: sort,
        onSort: onSort,
        selectedId: selectedId,
        onSelect: onSelect,
        fmt: fmt,
        colors: colors,
      );
    }
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

class _MobileBillList extends StatelessWidget {
  const _MobileBillList({
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

  static const _sortColumns = [
    ('billNumber', 'Number'),
    ('issueDate', 'Date'),
    ('total', 'Amount'),
    ('contactName', 'Vendor'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Mobile sort chips ─────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              for (final (id, label) in _sortColumns)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SortChip(
                    label: label,
                    columnId: id,
                    sort: sort,
                    onSort: onSort,
                    colors: colors,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item.id == selectedId;
        final overdue = item.status == BillStatus.unpaid &&
            DateTime.tryParse(item.dueDate)?.isBefore(DateTime.now()) == true;
        final numText = item.billNumber.isNotEmpty
            ? item.billNumber
            : 'Bill #${item.id.length >= 6 ? item.id.substring(0, 6) : item.id}';

        return Card(
          margin: EdgeInsets.zero,
          color: isSelected ? colors.primaryContainer : null,
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
                          numText,
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
                        label: _label(item.status),
                        tone: overdue ? StatusTone.danger : _tone(item.status),
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
                      Expanded(
                        child: Text(
                          overdue
                              ? '${item.issueDate} · Overdue ${item.dueDate}'
                              : '${item.issueDate} · Due ${item.dueDate}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: overdue ? colors.danger : colors.textMuted,
                          ),
                        ),
                      ),
                      if (item.outstanding > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${fmt.currency(item.outstanding)} due',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
        ),
      ],
    );
  }

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

/// Compact sort chip for the mobile sort strip.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.columnId,
    required this.sort,
    required this.onSort,
    required this.colors,
  });

  final String label;
  final String columnId;
  final TableSort sort;
  final void Function(String) onSort;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    final active = sort.columnId == columnId;
    final asc = sort.direction == SortDirection.ascending;
    return GestureDetector(
      onTap: () => onSort(columnId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.primary : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? colors.onPrimary : colors.textSecondary,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(
                asc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: colors.onPrimary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
