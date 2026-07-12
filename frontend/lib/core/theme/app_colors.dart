/// ApexBooks Design Language — semantic color tokens, spacing and radius
/// scales. The [ThemeData] builder lives in `app_theme.dart`.
library;

import 'package:flutter/material.dart';

/// Semantic color roles shared across light + dark themes.
///
/// Exposed on the theme via `Theme.of(context).extension<ApexColors>()!`.
@immutable
class ApexColors extends ThemeExtension<ApexColors> {
  const ApexColors({
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color skeletonBase;
  final Color skeletonHighlight;

  @override
  ApexColors copyWith({
    Color? primary,
    Color? primaryContainer,
    Color? onPrimary,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return ApexColors(
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  ApexColors lerp(ThemeExtension<ApexColors>? other, double t) {
    if (other is! ApexColors) return this;
    return ApexColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer: Color.lerp(
        primaryContainer,
        other.primaryContainer,
        t,
      )!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(
        skeletonHighlight,
        other.skeletonHighlight,
        t,
      )!,
    );
  }
}

/// Spacing scale based on an 8px grid.
class ApexSpacing {
  ApexSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Radius tokens.
class ApexRadius {
  ApexRadius._();
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;
}

/// Light theme semantic colors.
const lightApexColors = ApexColors(
  primary: Color(0xFF4F46E5),
  primaryContainer: Color(0xFFE0E7FF),
  onPrimary: Color(0xFFFFFFFF),
  accent: Color(0xFF7C3AED),
  success: Color(0xFF16A34A),
  warning: Color(0xFFD97706),
  danger: Color(0xFFDC2626),
  info: Color(0xFF0EA5E9),
  surface: Color(0xFFFFFFFF),
  surfaceRaised: Color(0xFFFFFFFF),
  surfaceMuted: Color(0xFFF5F6FA),
  border: Color(0xFFE5E7EB),
  textPrimary: Color(0xFF111827),
  textSecondary: Color(0xFF4B5563),
  textMuted: Color(0xFF9CA3AF),
  skeletonBase: Color(0xFFECEFF3),
  skeletonHighlight: Color(0xFFF7F8FB),
);

/// Dark theme semantic colors.
const darkApexColors = ApexColors(
  primary: Color(0xFF818CF8),
  primaryContainer: Color(0xFF3730A3),
  onPrimary: Color(0xFF1E1B4B),
  accent: Color(0xFFA78BFA),
  success: Color(0xFF4ADE80),
  warning: Color(0xFFFBBF24),
  danger: Color(0xFFF87171),
  info: Color(0xFF38BDF8),
  surface: Color(0xFF0F1117),
  surfaceRaised: Color(0xFF1A1D27),
  surfaceMuted: Color(0xFF232734),
  border: Color(0xFF2C313F),
  textPrimary: Color(0xFFF3F4F6),
  textSecondary: Color(0xFFCBD5E1),
  textMuted: Color(0xFF8590A2),
  skeletonBase: Color(0xFF232734),
  skeletonHighlight: Color(0xFF2C313F),
);

/// Convenience accessor for the [ApexColors] extension of the current theme.
ApexColors apexColors(BuildContext context) =>
    Theme.of(context).extension<ApexColors>()!;
