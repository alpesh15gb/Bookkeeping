import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';

class AppLoadingSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const AppLoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppRadius.sm,
  });

  @override
  State<AppLoadingSkeleton> createState() => _AppLoadingSkeletonState();
}

class _AppLoadingSkeletonState extends State<AppLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(
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
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [
                AppColors.gray200,
                AppColors.gray100.withOpacity(0.5 + _animation.value * 0.5),
                AppColors.gray200,
              ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ].map((s) => s.clamp(0.0, 1.0)).toList(),
            ),
          ),
        );
      },
    );
  }
}

class AppLoadingCard extends StatelessWidget {
  const AppLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppLoadingSkeleton(width: 32, height: 32),
          const SizedBox(height: AppSpacing.md),
          AppLoadingSkeleton(width: 100, height: 12),
          const SizedBox(height: AppSpacing.sm),
          AppLoadingSkeleton(width: 80, height: 24),
        ],
      ),
    );
  }
}

class AppLoadingRow extends StatelessWidget {
  const AppLoadingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          AppLoadingSkeleton(width: 40, height: 16),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: AppLoadingSkeleton(width: double.infinity, height: 16)),
          const SizedBox(width: AppSpacing.lg),
          AppLoadingSkeleton(width: 100, height: 16),
          const SizedBox(width: AppSpacing.lg),
          AppLoadingSkeleton(width: 80, height: 16),
          const SizedBox(width: AppSpacing.lg),
          AppLoadingSkeleton(width: 80, height: 24),
        ],
      ),
    );
  }
}
