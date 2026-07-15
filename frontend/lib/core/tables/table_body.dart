/// Internal table body renderer for [ApexDataTable]: the sticky-header
/// [DataTable] with sortable columns, row selection and focus highlighting.
/// Kept separate so the public [ApexDataTable] widget stays focused.
library;

import 'package:flutter/material.dart';

import '../api/base_model.dart';
import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import '../utils/formatters.dart';
import 'table_column.dart';
import 'table_controller.dart';

/// Renders the data rows as a horizontally-scrollable [DataTable].
class ApexTableBody<T extends BaseModel> extends StatelessWidget {
  const ApexTableBody({
    super.key,
    required this.controller,
    required this.columns,
    required this.rows,
    required this.focusedRow,
    required this.onRowTap,
    required this.rowKey,
  });

  final ApexTableController controller;
  final List<ApexColumn<T>> columns;
  final List<T> rows;
  final int focusedRow;
  final void Function(T)? onRowTap;
  final String Function(T) rowKey;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final visibleCols = columns
        .where((c) => !controller.value.hiddenColumns.contains(c.id))
        .toList();
    final allSelected =
        rows.isNotEmpty &&
        rows.every((r) => controller.value.selectedIds.contains(rowKey(r)));
    final isMobile = ResponsiveLayout.isMobile(context);

    if (isMobile) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final row = rows[i];
          final selected = controller.value.selectedIds.contains(rowKey(row));
          final cardColumns = visibleCols.take(4).toList();
          return Card(
            margin: EdgeInsets.zero,
            color: selected ? colors.primaryContainer : colors.surfaceRaised,
            child: InkWell(
              borderRadius: BorderRadius.circular(ApexRadius.lg),
              onTap: onRowTap == null ? null : () => onRowTap!(row),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: selected,
                      onChanged: (_) => controller.toggleSelection(rowKey(row)),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        children: List.generate(cardColumns.length, (
                          columnIndex,
                        ) {
                          final column = cardColumns[columnIndex];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: columnIndex == cardColumns.length - 1
                                  ? 0
                                  : 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 86,
                                  child: Text(
                                    column.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colors.textMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Expanded(
                                  child: DefaultTextStyle.merge(
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: colors.textPrimary,
                                          fontWeight: columnIndex == 0
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                    child:
                                        column.cellBuilder?.call(
                                          context,
                                          row,
                                          i,
                                        ) ??
                                        Text(
                                          _stringify(column.readValue(row)),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                    if (onRowTap != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(colors.surfaceMuted),
        dataRowMinHeight: isMobile ? 48 : 38,
        dataRowMaxHeight: isMobile ? 48 : 38,
        showCheckboxColumn: true,
        columnSpacing: isMobile ? 12 : 16,
        horizontalMargin: isMobile ? 8 : 12,
        columns: [
          DataColumn(
            label: Checkbox(
              value: allSelected,
              onChanged: (v) => v == null
                  ? null
                  : v
                  ? controller.selectAll(rows.map(rowKey))
                  : controller.clearSelection(),
            ),
          ),
          ...visibleCols.map(
            (c) => DataColumn(
              onSort: c.sortable ? (_, _) => controller.toggleSort(c.id) : null,
              label: _HeaderLabel<T>(
                column: c,
                isSorted: controller.value.sort.columnId == c.id,
                direction: controller.value.sort.direction,
              ),
            ),
          ),
        ],
        rows: List.generate(rows.length, (i) {
          final row = rows[i];
          final selected = controller.value.selectedIds.contains(rowKey(row));
          final focused = i == focusedRow;
          return DataRow(
            selected: selected,
            onSelectChanged: (v) => controller.toggleSelection(rowKey(row)),
            color: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.selected)) {
                return colors.primaryContainer;
              }
              if (states.contains(WidgetState.hovered)) {
                return colors.surfaceMuted;
              }
              if (focused) return colors.surfaceMuted;
              return null;
            }),
            cells: [
              DataCell(
                Checkbox(
                  value: selected,
                  onChanged: (v) => controller.toggleSelection(rowKey(row)),
                ),
              ),
              ...visibleCols.map(
                (c) => DataCell(
                  RepaintBoundary(
                    child:
                        c.cellBuilder?.call(context, row, i) ??
                        Text(
                          _stringify(c.readValue(row)),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                  ),
                  onTap: onRowTap == null ? null : () => onRowTap!(row),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  String _stringify(Object? v) {
    if (v == null) return '—';
    if (v is num) return formatNumber(v);
    return v.toString();
  }
}

class _HeaderLabel<T extends BaseModel> extends StatelessWidget {
  const _HeaderLabel({
    required this.column,
    required this.isSorted,
    required this.direction,
  });
  final ApexColumn<T> column;
  final bool isSorted;
  final SortDirection direction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(column.label, style: Theme.of(context).textTheme.labelLarge),
        if (column.sortable) ...[
          const SizedBox(width: 4),
          Icon(
            isSorted
                ? (direction == SortDirection.ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                : Icons.unfold_more_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );
  }
}
