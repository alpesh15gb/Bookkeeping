import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderWidth;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;
  final bool isCompact;
  final double? width;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth,
    this.shadow,
    this.onTap,
    this.isCompact = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cardPadding = EdgeInsets.all(isCompact ? AppSpacing.md : AppSpacing.cardPadding);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: margin,
        padding: padding ?? cardPadding,
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: borderColor ?? AppColors.gray200,
            width: borderWidth ?? 1,
          ),
          boxShadow: shadow ?? AppShadow.card,
        ),
        child: child,
      ),
    );
  }
}
