/// Reusable skeleton loader widgets for loading states.
/// DESIGN.md mandates "Loading skeleton while data fetches" for every list screen.
/// These shimmer-animated placeholders match the actual layout shapes.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/theme/app_colors.dart';

/// A full-page or content-area skeleton loader.
class ApexSkeletonLoader extends StatelessWidget {
  const ApexSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShimmerSkeleton(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: 200, height: 18),
              SizedBox(height: 16),
              SkeletonBox(width: 280, height: 14),
              SizedBox(height: 8),
              SkeletonBox(width: 240, height: 14),
              SizedBox(height: 24),
              SkeletonBox(width: double.infinity, height: 48),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 48),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single shimmer-animated skeleton rectangle.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.skeletonBase,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// A shimmer-animated skeleton block that pulses between base and highlight colors.
class ShimmerSkeleton extends StatefulWidget {
  const ShimmerSkeleton({super.key, required this.child});

  final Widget child;

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(opacity: _animation.value, child: child);
      },
      child: widget.child,
    );
  }
}

/// A KPI card skeleton that matches the dashboard KPI card layout.
class KpiCardSkeleton extends StatelessWidget {
  const KpiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: apexColors(context).skeletonBase,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(
            color: apexColors(context).border.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(
              width: 36,
              height: 36,
              borderRadius: BorderRadius.circular(ApexRadius.sm),
            ),
            const SizedBox(height: 14),
            const SkeletonBox(width: 80, height: 12),
            const SizedBox(height: 6),
            const SkeletonBox(width: 120, height: 24),
            const SizedBox(height: 8),
            const SkeletonBox(width: 90, height: 11),
          ],
        ),
      ),
    );
  }
}

/// A table row skeleton that matches the data table row layout.
class TableRowSkeleton extends StatelessWidget {
  const TableRowSkeleton({super.key, this.columns = 5, this.columnWidths});

  final int columns;
  final List<double>? columnWidths;

  @override
  Widget build(BuildContext context) {
    final widths = columnWidths ?? List.filled(columns, 80.0);
    return ShimmerSkeleton(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: apexColors(context).border.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            for (int i = 0; i < columns; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              SkeletonBox(width: widths[i], height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

/// A list item skeleton that matches a card-based list layout.
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ShimmerSkeleton(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(color: colors.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            SkeletonBox(
              width: 40,
              height: 40,
              borderRadius: BorderRadius.circular(ApexRadius.sm),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 160, height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(width: 100, height: 11),
                ],
              ),
            ),
            SkeletonBox(
              width: 60,
              height: 24,
              borderRadius: BorderRadius.circular(ApexRadius.pill),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page header skeleton.
class PageHeaderSkeleton extends StatelessWidget {
  const PageHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 200, height: 26),
                SizedBox(height: 6),
                SkeletonBox(width: 300, height: 14),
              ],
            ),
          ),
          SkeletonBox(
            width: 120,
            height: 40,
            borderRadius: BorderRadius.circular(ApexRadius.md),
          ),
        ],
      ),
    );
  }
}

/// A detail section skeleton.
class DetailSectionSkeleton extends StatelessWidget {
  const DetailSectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ShimmerSkeleton(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(color: colors.border.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 120, height: 16),
            const SizedBox(height: 12),
            for (int i = 0; i < 4; i++) ...[
              const Row(
                children: [
                  SkeletonBox(width: 100, height: 13),
                  SizedBox(width: 12),
                  SkeletonBox(width: 150, height: 13),
                ],
              ),
              if (i < 3) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
