/// ApexBooks Design Language — semantic color tokens, spacing and radius
/// scales. The [ThemeData] builder lives in `app_theme.dart`.
library;

import 'package:flutter/material.dart';

/// Re-export spacing/radius tokens
export 'spacing.dart' show ApexSpacing, ApexRadius;

/// Re-export design-system top-level spacing/radius constants
export '../design_system/tokens/spacing.dart';

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
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
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
      skeletonHighlight: Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
    );
  }

  /// Material 3–style container roles for convenience.
  Color get successContainer => success.withValues(alpha: 0.12);
  Color get warningContainer => warning.withValues(alpha: 0.12);
  Color get dangerContainer => danger.withValues(alpha: 0.12);
  Color get infoContainer => info.withValues(alpha: 0.12);
  Color get errorContainer => danger.withValues(alpha: 0.12);
  Color get error => danger;

  /// Light theme palette.
  static const light = ApexColors(
    primary: Color(0xFF1A5D3E),
    primaryContainer: Color(0xFFE8F5ED),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF1A5D3E),
    success: Color(0xFF1E8A49),
    warning: Color(0xFFB45309),
    danger: Color(0xFFC62828),
    info: Color(0xFF0288D1),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF5F5F5),
    surfaceMuted: Color(0xFFF5F5F5),
    border: Color(0xFFE0E0E0),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF5F5F5F),
    textMuted: Color(0xFF9E9E9E),
    skeletonBase: Color(0xFFE0E0E0),
    skeletonHighlight: Color(0xFFF5F5F5),
  );

  /// Dark theme palette.
  static const dark = ApexColors(
    primary: Color(0xFF4ADE80),
    primaryContainer: Color(0xFF1B3A2E),
    onPrimary: Color(0xFF000000),
    accent: Color(0xFF4ADE80),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF5350),
    info: Color(0xFF29B6F6),
    surface: Color(0xFF1E1E1E),
    surfaceRaised: Color(0xFF2D2D2D),
    surfaceMuted: Color(0xFF2D2D2D),
    border: Color(0xFF3D3D3D),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    textMuted: Color(0xFF757575),
    skeletonBase: Color(0xFF3D3D3D),
    skeletonHighlight: Color(0xFF4D4D4D),
  );
}

/// Convenience accessor for the color extension.
ApexColors apexColors(BuildContext context) =>
    Theme.of(context).extension<ApexColors>()!;