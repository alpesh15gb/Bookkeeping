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
                    child: c.cellBuilder?.call(context, row, i) ??
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
