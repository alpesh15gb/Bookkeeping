import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}

class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 120, height: 18, borderRadius: BorderRadius.circular(4)),
              SkeletonBox(width: 60, height: 18, borderRadius: BorderRadius.circular(4)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SkeletonBox(width: 14, height: 14),
              const SizedBox(width: 8),
              SkeletonBox(width: 100, height: 14, borderRadius: BorderRadius.circular(2)),
              const SizedBox(width: 20),
              const SkeletonBox(width: 14, height: 14),
              const SizedBox(width: 8),
              SkeletonBox(width: 80, height: 14, borderRadius: BorderRadius.circular(2)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 90, height: 22, borderRadius: BorderRadius.circular(4)),
              SkeletonBox(width: 70, height: 26, borderRadius: BorderRadius.circular(4)),
            ],
          ),
        ],
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  final int count;
  const ListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: count,
      itemBuilder: (context, index) => const CardSkeleton(),
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 28, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 6),
                  SkeletonBox(width: 220, height: 14, borderRadius: BorderRadius.circular(2)),
                ],
              ),
              const SkeletonBox(width: 80, height: 34),
            ],
          ),
          const SizedBox(height: 24),
          // Metric Cards Grid
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            children: List.generate(4, (index) => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: AppRadius.card,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 32, height: 32),
                  const Spacer(),
                  SkeletonBox(width: 100, height: 20, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 6),
                  SkeletonBox(width: 60, height: 12, borderRadius: BorderRadius.circular(2)),
                ],
              ),
            )),
          ),
          const SizedBox(height: 24),
          // Graph skeleton
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 16, borderRadius: BorderRadius.circular(4)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(6, (index) => Column(
                    children: [
                      SkeletonBox(width: 20, height: 40 + (index * 20.0), borderRadius: BorderRadius.circular(2)),
                      const SizedBox(height: 8),
                      SkeletonBox(width: 24, height: 10, borderRadius: BorderRadius.circular(1)),
                    ],
                  )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Recent items section skeleton
          SkeletonBox(width: 130, height: 18, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 12),
          Column(
            children: List.generate(3, (index) => Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: AppRadius.card,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const SkeletonBox(width: 36, height: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120, height: 14, borderRadius: BorderRadius.circular(2)),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 80, height: 10, borderRadius: BorderRadius.circular(2)),
                      ],
                    ),
                  ),
                  const SkeletonBox(width: 60, height: 14),
                ],
              ),
            )),
          ),
        ],
      ),
    );
  }
}
