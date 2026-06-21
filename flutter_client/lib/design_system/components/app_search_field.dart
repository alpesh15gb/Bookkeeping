import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import '../tokens/spacing.dart';

class AppSearchField extends StatelessWidget {
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final bool autofocus;
  final Widget? prefixIcon;
  final Widget? suffix;
  final double? width;

  const AppSearchField({
    super.key,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.autofocus = false,
    this.prefixIcon,
    this.suffix,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: AppTypography.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText ?? 'Search...',
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.gray400,
          ),
          prefixIcon: prefixIcon ?? const Icon(
            Icons.search,
            size: 18,
            color: AppColors.gray400,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.gray50,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.gray200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.gray200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}
