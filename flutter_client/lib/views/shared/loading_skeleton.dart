import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

// ═══════════════════════════════════════════════════════════════════
// SHIMMER / SKELETON LOADING WIDGETS
// ═══════════════════════════════════════════════════════════════════

/// A single shimmer placeholder block.
///
/// Wraps a [BoxDecoration] with a subtle animated opacity to create
/// a skeleton-loading effect. Provide an [opacity] value (0–1) to
/// control the shimmer intensity.
class LoadingSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final double opacity;

  const LoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.opacity = 0.4,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 800),
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

/// A list of skeleton rows — useful for loading table rows or list items.
///
/// Each row is a horizontal strip with optional avatar and trailing placeholders.
class ListSkeleton extends StatelessWidget {
  final int rowCount;
  final bool hasAvatar;
  final bool hasTrailing;
  final double rowHeight;
  final double spacing;

  const ListSkeleton({
    super.key,
    this.rowCount = 5,
    this.hasAvatar = false,
    this.hasTrailing = false,
    this.rowHeight = 16,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(rowCount, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index < rowCount - 1 ? spacing : 0),
          child: _SkeletonRow(
            rowHeight: rowHeight,
            hasAvatar: hasAvatar,
            hasTrailing: hasTrailing,
          ),
        );
      }),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final double rowHeight;
  final bool hasAvatar;
  final bool hasTrailing;

  const _SkeletonRow({
    required this.rowHeight,
    required this.hasAvatar,
    required this.hasTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasAvatar) ...[
          LoadingSkeleton(
            width: rowHeight * 2,
            height: rowHeight * 2,
            borderRadius: BorderRadius.circular(rowHeight),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoadingSkeleton(
                width: double.infinity,
                height: rowHeight,
              ),
              const SizedBox(height: AppSpacing.xs),
              LoadingSkeleton(
                width: rowHeight * 4,
                height: rowHeight * 0.7,
              ),
            ],
          ),
        ),
        if (hasTrailing) ...[
          const SizedBox(width: AppSpacing.md),
          LoadingSkeleton(
            width: rowHeight * 3,
            height: rowHeight,
          ),
        ],
      ],
    );
  }
}

/// A table-like skeleton with rows and columns.
///
/// Useful for loading tabular data with a header row and data rows.
class TableSkeleton extends StatelessWidget {
  final int rowCount;
  final int columnCount;
  final bool hasHeader;
  final double rowHeight;
  final List<double>? columnWidths;

  const TableSkeleton({
    super.key,
    this.rowCount = 5,
    this.columnCount = 4,
    this.hasHeader = true,
    this.rowHeight = 14,
    this.columnWidths,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (hasHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: List.generate(columnCount, (colIndex) {
                final w =
                    columnWidths != null && colIndex < columnWidths!.length
                        ? columnWidths![colIndex]
                        : null;
                return Expanded(
                  flex: w != null ? 0 : 1,
                  child: w != null
                      ? SizedBox(
                          width: w,
                          child: _skeletonBar(rowHeight * 0.8),
                        )
                      : _skeletonBar(rowHeight * 0.8),
                );
              }),
            ),
          ),
        ...List.generate(rowCount, (rowIndex) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: rowIndex < rowCount - 1 ? AppSpacing.md : 0,
            ),
            child: Row(
              children: List.generate(columnCount, (colIndex) {
                final w =
                    columnWidths != null && colIndex < columnWidths!.length
                        ? columnWidths![colIndex]
                        : null;
                return Expanded(
                  flex: w != null ? 0 : 1,
                  child: w != null
                      ? SizedBox(width: w, child: _skeletonBar(rowHeight))
                      : _skeletonBar(rowHeight),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _skeletonBar(double height) {
    return LoadingSkeleton(
      width: double.infinity,
      height: height,
      opacity: 0.3,
    );
  }
}

/// A card-shaped skeleton placeholder.
///
/// Mimics the shape of an [AppCard] with placeholder content inside.
class CardSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final EdgeInsetsGeometry? padding;
  final bool hasImage;
  final bool hasActions;

  const CardSkeleton({
    super.key,
    this.width,
    this.height = 120,
    this.padding,
    this.hasImage = false,
    this.hasActions = false,
  });

  static const double _rowH = 14;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage) ...[
            LoadingSkeleton(
              width: double.infinity,
              height: 48,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          LoadingSkeleton(
            width: width != null ? width! * 0.6 : 120,
            height: _rowH,
          ),
          const SizedBox(height: AppSpacing.sm),
          LoadingSkeleton(
            width: double.infinity,
            height: _rowH * 0.7,
          ),
          const SizedBox(height: AppSpacing.xs),
          LoadingSkeleton(
            width: width != null ? width! * 0.4 : 80,
            height: _rowH * 0.7,
          ),
          if (hasActions) ...[
            const Spacer(),
            Row(
              children: [
                LoadingSkeleton(
                  width: 64,
                  height: 28,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                const SizedBox(width: AppSpacing.sm),
                LoadingSkeleton(
                  width: 64,
                  height: 28,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
