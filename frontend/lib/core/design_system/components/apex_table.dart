/// Advanced data table with sorting, filtering, selection, pagination, and responsive modes.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';

/// Column definition for ApexTable.
class ApexColumn<T> {
  const ApexColumn({
    required this.id,
    required this.label,
    required this.value,
    this.width = 160.0,
    this.minWidth = 80.0,
    this.maxWidth = 400.0,
    this.alignment = Alignment.centerLeft,
    this.sortable = false,
    this.filterable = false,
    this.visible = true,
    this.cellBuilder,
    this.headerBuilder,
    this.filterOptions,
    this.pinned = false,
  });

  final String id;
  final String label;
  final T Function(dynamic row) value;
  final double width;
  final double minWidth;
  final double maxWidth;
  final Alignment alignment;
  final bool sortable;
  final bool filterable;
  final bool visible;
  final Widget Function(BuildContext context, dynamic row, T value)? cellBuilder;
  final Widget Function(BuildContext context, VoidCallback onSort)? headerBuilder;
  final List<String>? filterOptions;
  final bool pinned; // For horizontal scroll - pinned columns stay visible
}

/// Sort state for a column.
class TableSort {
  const TableSort({this.columnId, this.ascending = true});
  final String? columnId;
  final bool ascending;
}

/// Row selection state.
class TableSelection<T> {
  const TableSelection({this.selectedIds = const <String>{}, this.selectAll = false});
  final Set<String> selectedIds;
  final bool selectAll; // For "select all pages" concept
}

/// Pagination state.
class TablePagination {
  const TablePagination({this.page = 0, this.pageSize = 25, this.total = 0});
  final int page;
  final int pageSize;
  final int total;

  int get totalPages => (total / pageSize).ceil();
  bool get hasNextPage => page < totalPages - 1;
  bool get hasPreviousPage => page > 0;
}

/// Main data table component.
class ApexTable<T> extends StatefulWidget {
  const ApexTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.getRowId,
    this.sort,
    this.onSort,
    this.selection,
    this.onSelectionChanged,
    this.pagination,
    this.onPaginationChanged,
    this.loading = false,
    this.emptyState,
    this.rowHeight = 52.0,
    this.headerHeight = 48.0,
    this.showCheckboxColumn = false,
    this.showRowNumbers = false,
    this.stickyHeader = true,
    this.horizontalScroll = true,
    this.onRowTap,
    this.onRowDoubleTap,
    this.rowBuilder,
  });

  final List<ApexColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) getRowId;
  final TableSort? sort;
  final ValueChanged<TableSort>? onSort;
  final TableSelection<T>? selection;
  final ValueChanged<TableSelection<T>>? onSelectionChanged;
  final TablePagination? pagination;
  final ValueChanged<TablePagination>? onPaginationChanged;
  final bool loading;
  final Widget? emptyState;
  final double rowHeight;
  final double headerHeight;
  final bool showCheckboxColumn;
  final bool showRowNumbers;
  final bool stickyHeader;
  final bool horizontalScroll;
  final void Function(T row)? onRowTap;
  final void Function(T row)? onRowDoubleTap;
  final Widget Function(BuildContext context, T row, int index)? rowBuilder;

  @override
  State<ApexTable<T>> createState() => _ApexTableState<T>();
}

class _ApexTableState<T> extends State<ApexTable<T>> {
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final visibleColumns = widget.columns.where((c) => c.visible).toList();

    if (widget.loading) {
      return _buildSkeleton(context, visibleColumns.length);
    }

    if (widget.rows.isEmpty) {
      return widget.emptyState ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart_outlined, size: 48, color: colors.textMuted),
                  const SizedBox(height: 16),
                  Text('No data available', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
          );
    }

    if (isMobile && visibleColumns.length > 4) {
      return _buildMobileCards(context, visibleColumns);
    }

    return _buildDesktopTable(context, visibleColumns);
  }

  Widget _buildSkeleton(BuildContext context, int columnCount) {
    final colors = apexColors(context);
    return Column(
      children: List.generate(5, (index) => _SkeletonRow(columnCount: columnCount, colors: colors)),
    );
  }

  Widget _buildMobileCards(BuildContext context, List<ApexColumn<T>> columns) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widget.rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final row = widget.rows[index];
        final rowId = widget.getRowId(row);
        final isSelected = widget.selection?.selectedIds.contains(rowId) ?? false;

        return Card(
          elevation: isSelected ? 2 : 1,
          color: isSelected ? colors.primaryContainer.withValues(alpha: 0.3) : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? colors.primary : colors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => widget.onRowTap?.call(row),
            onDoubleTap: () => widget.onRowDoubleTap?.call(row),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: columns.map((col) {
                  final value = col.value(row);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            col.label,
                            style: textTheme.labelSmall?.copyWith(color: colors.textSecondary),
                          ),
                        ),
                        Expanded(
                          child: col.cellBuilder != null
                              ? col.cellBuilder!(context, row, value)
                              : Text(
                                  value?.toString() ?? '',
                                  style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
                                ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTable(BuildContext context, List<ApexColumn<T>> columns) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // Table with sticky header
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    child: Column(
                      children: [
                        // Header
                        _buildHeader(context, columns, colors, textTheme),
                        // Rows
                        ...widget.rows.asMap().entries.map((entry) {
                          final index = entry.key;
                          final row = entry.value;
                          return _buildRow(context, row, index, columns, colors, textTheme);
                        }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Pagination
        if (widget.pagination != null) _buildPagination(context, colors),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, List<ApexColumn<T>> columns, ApexColors colors, TextTheme textTheme) {
    final selection = widget.selection;

    return Container(
      height: widget.headerHeight,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Checkbox column
          if (widget.showCheckboxColumn)
            SizedBox(
              width: 48,
              child: Checkbox(
                value: selection?.selectAll ?? false,
                tristate: true,
                onChanged: (value) {
                  widget.onSelectionChanged?.call(
                    TableSelection<T>(
                      selectedIds: value == true
                          ? widget.rows.map(widget.getRowId).toSet()
                          : <String>{},
                      selectAll: value == true,
                    ),
                  );
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          // Row number column
          if (widget.showRowNumbers)
            SizedBox(
              width: 48,
              child: Center(
                child: Text('#', style: textTheme.labelSmall?.copyWith(color: colors.textSecondary)),
              ),
            ),
          // Data columns
          ...columns.map((col) => _buildHeaderCell(context, col, colors, textTheme)),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, ApexColumn<T> col, ApexColors colors, TextTheme textTheme) {
    final sort = widget.sort;
    final isSorted = sort?.columnId == col.id;

    return Container(
      width: col.width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: col.alignment,
      child: col.headerBuilder != null
          ? col.headerBuilder!(
              context,
              col.sortable && widget.onSort != null
                  ? () => widget.onSort!(
                        TableSort(columnId: col.id, ascending: !(sort?.ascending ?? true)),
                      )
                  : () {},
            )
          : InkWell(
              onTap: col.sortable && widget.onSort != null
                  ? () => widget.onSort!(
                        TableSort(columnId: col.id, ascending: !(sort?.ascending ?? true)),
                      )
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      col.label,
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (col.sortable) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isSorted
                            ? (sort!.ascending ? Icons.arrow_upward : Icons.arrow_downward)
                            : Icons.unfold_more,
                        size: 14,
                        color: isSorted ? colors.primary : colors.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    T row,
    int index,
    List<ApexColumn<T>> columns,
    ApexColors colors,
    TextTheme textTheme,
  ) {
    final rowId = widget.getRowId(row);
    final isSelected = widget.selection?.selectedIds.contains(rowId) ?? false;
    final isEven = index.isEven;

    return InkWell(
      onTap: () => widget.onRowTap?.call(row),
      onDoubleTap: () => widget.onRowDoubleTap?.call(row),
      child: Container(
        height: widget.rowHeight,
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primaryContainer.withValues(alpha: 0.3)
              : (isEven ? colors.surface : colors.surfaceMuted.withValues(alpha: 0.3)),
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Checkbox column
            if (widget.showCheckboxColumn)
              SizedBox(
                width: 48,
                child: Center(
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      final newSelection = Set<String>.from(widget.selection?.selectedIds ?? {});
                      if (value == true) {
                        newSelection.add(rowId);
                      } else {
                        newSelection.remove(rowId);
                      }
                      widget.onSelectionChanged?.call(
                        TableSelection<T>(selectedIds: newSelection),
                      );
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            // Row number column
            if (widget.showRowNumbers)
              SizedBox(
                width: 48,
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
                  ),
                ),
              ),
            // Data columns
            ...columns.map((col) => _buildCell(context, row, col, colors, textTheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    T row,
    ApexColumn<T> col,
    ApexColors colors,
    TextTheme textTheme,
  ) {
    final value = col.value(row);

    return Container(
      width: col.width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: col.alignment,
      child: col.cellBuilder != null
          ? col.cellBuilder!(context, row, value)
          : Text(
              value?.toString() ?? '',
              style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
    );
  }

  Widget _buildPagination(BuildContext context, ApexColors colors) {
    final pagination = widget.pagination!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            'Showing ${pagination.page * pagination.pageSize + 1} to ${(pagination.page + 1) * pagination.pageSize > pagination.total ? pagination.total : (pagination.page + 1) * pagination.pageSize} of ${pagination.total}',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.chevron_left, color: colors.textPrimary),
            onPressed: pagination.hasPreviousPage
                ? () => widget.onPaginationChanged?.call(
                      TablePagination(
                        page: pagination.page - 1,
                        pageSize: pagination.pageSize,
                        total: pagination.total,
                      ),
                    )
                : null,
            tooltip: 'Previous page',
          ),
          Text(
            '${pagination.page + 1} / ${pagination.totalPages}',
            style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: colors.textPrimary),
            onPressed: pagination.hasNextPage
                ? () => widget.onPaginationChanged?.call(
                      TablePagination(
                        page: pagination.page + 1,
                        pageSize: pagination.pageSize,
                        total: pagination.total,
                      ),
                    )
                : null,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.columnCount, required this.colors});
  final int columnCount;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: List.generate(columnCount + 1, (index) {
          return Expanded(
            child: Container(
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: colors.skeletonBase,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Mobile-optimized card list for tables.
class ApexCardList<T> extends StatelessWidget {
  const ApexCardList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.emptyState,
    this.loading = false,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? emptyState;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);

    if (loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, _) => _SkeletonCard(colors: colors),
      );
    }

    if (items.isEmpty) {
      return emptyState ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: colors.textMuted),
                  const SizedBox(height: 16),
                  Text('No items', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
          );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => itemBuilder(context, items[index], index),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.colors});
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 16, width: 120, color: colors.skeletonBase),
            const SizedBox(height: 12),
            Container(height: 12, width: 200, color: colors.skeletonBase),
            const SizedBox(height: 8),
            Container(height: 12, width: 150, color: colors.skeletonBase),
          ],
        ),
      ),
    );
  }
}