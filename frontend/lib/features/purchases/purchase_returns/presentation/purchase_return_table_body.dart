import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../models/purchase_return.dart';
import '../models/purchase_return_status.dart';

/// Sticky-header, sortable table for purchase returns.
class PurchaseReturnTableBody extends StatelessWidget {
  const PurchaseReturnTableBody({
    super.key,
    required this.items,
    required this.sort,
    required this.onSort,
    required this.selectedId,
    required this.onSelect,
    required this.fmt,
    required this.colors,
  });

  final List<PurchaseReturnListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(PurchaseReturnListItem) onSelect;
  final NumberFormatter fmt;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return _MobilePurchaseReturnList(
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 720,
        child: Column(
          children: [
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _hd(context, 'Return No.', 'returnNumber', 180),
                  _hd(context, 'Vendor', 'contactName', 220),
                  _hd(context, 'Return Date', 'returnDate', 120),
                  _hd(context, 'Total', 'total', 110, right: true),
                  const SizedBox(
                    width: 110,
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
                  final selected = item.id == selectedId;
                  final numText = item.returnNumber.isNotEmpty
                      ? item.returnNumber
                      : 'DN #${item.id.length >= 6 ? item.id.substring(0, 6) : item.id}';
                  return InkWell(
                    onTap: () => onSelect(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      color: selected ? colors.primaryContainer : null,
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
                            width: 220,
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
                              item.returnDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              fmt.currency(item.total),
                              textAlign: TextAlign.right,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
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
  }

  Widget _hd(
    BuildContext context,
    String label,
    String columnId,
    double width, {
    bool right = false,
  }) {
    final isSorted = sort.columnId == columnId;
    final asc = sort.direction == SortDirection.ascending;
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => onSort(columnId),
        child: Row(
          mainAxisAlignment: right
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

  StatusTone _tone(PurchaseReturnStatus s) => switch (s) {
    PurchaseReturnStatus.draft => StatusTone.neutral,
    PurchaseReturnStatus.posted => StatusTone.success,
    PurchaseReturnStatus.cancelled => StatusTone.danger,
  };
}

class _MobilePurchaseReturnList extends StatelessWidget {
  const _MobilePurchaseReturnList({
    required this.items,
    required this.sort,
    required this.onSort,
    required this.selectedId,
    required this.onSelect,
    required this.fmt,
    required this.colors,
  });

  final List<PurchaseReturnListItem> items;
  final TableSort sort;
  final void Function(String columnId) onSort;
  final String? selectedId;
  final void Function(PurchaseReturnListItem) onSelect;
  final NumberFormatter fmt;
  final ApexColors colors;

  static const _sortColumns = [
    ('returnNumber', 'Number'),
    ('returnDate', 'Date'),
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
                  child: _PRSortChip(
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
              final numText = item.returnNumber.isNotEmpty
                  ? item.returnNumber
                  : 'DN #${item.id.length >= 6 ? item.id.substring(0, 6) : item.id}';

              return Card(
                margin: EdgeInsets.zero,
                color: isSelected ? colors.primaryContainer : null,
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
                                numText,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              fmt.currency(item.total),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
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
                                style:
                                    TextStyle(color: colors.textSecondary),
                              ),
                            ),
                            StatusBadge(
                              label: item.status.value,
                              tone: _tone(item.status),
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
                              'Returned ${item.returnDate}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
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
          ),
        ),
      ],
    );
  }

  StatusTone _tone(PurchaseReturnStatus s) => switch (s) {
    PurchaseReturnStatus.draft => StatusTone.neutral,
    PurchaseReturnStatus.posted => StatusTone.success,
    PurchaseReturnStatus.cancelled => StatusTone.danger,
  };
}

/// Compact sort chip for the purchase-return mobile sort strip.
class _PRSortChip extends StatelessWidget {
  const _PRSortChip({
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
