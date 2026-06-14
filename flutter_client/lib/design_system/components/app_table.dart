import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

class TableColumn {
  final String label;
  final double? width;
  final bool isSortable;
  final Alignment alignment;

  const TableColumn({
    required this.label,
    this.width,
    this.isSortable = false,
    this.alignment = Alignment.centerLeft,
  });
}

class AppTable extends StatelessWidget {
  final List<TableColumn> columns;
  final List<Widget> rows;
  final bool showCheckbox;
  final bool headerSortable;
  final Function(int)? onSort;

  const AppTable({
    super.key,
    required this.columns,
    required this.rows,
    this.showCheckbox = false,
    this.headerSortable = false,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: AppColors.gray200),
          ...rows.map((row) {
            if (row is AppTableRow) {
              return _buildRow(row);
            }
            return row;
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRow(AppTableRow row) {
    return GestureDetector(
      onTap: row.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: row.backgroundColor ?? AppColors.white,
          border: Border(
            bottom: BorderSide(
              color: row.borderColor ?? AppColors.gray100,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            if (showCheckbox) ...[
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: row.isSelected,
                  onChanged: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
            ...List.generate(row.cells.length, (index) {
              if (index < columns.length) {
                final col = columns[index];
                return SizedBox(
                  width: col.width,
                  child: Align(
                    alignment: col.alignment,
                    child: row.cells[index],
                  ),
                );
              }
              return row.cells[index];
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      color: AppColors.gray50,
      child: Row(
        children: [
          if (showCheckbox) ...[
            SizedBox(
              width: 40,
              child: Checkbox(
                value: false,
                onChanged: (_) {},
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
          ...columns.map((col) => SizedBox(
            width: col.width,
            child: Align(
              alignment: col.alignment,
              child: Text(
                col.label.toUpperCase(),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.gray500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

class AppTableRow extends StatelessWidget {
  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool isSelected;
  final Color? backgroundColor;
  final Color? borderColor;

  const AppTableRow({
    super.key,
    required this.cells,
    this.onTap,
    this.isSelected = false,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.white,
          border: Border(
            bottom: BorderSide(
              color: borderColor ?? AppColors.gray100,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: cells,
        ),
      ),
    );
  }
}
