/// ApexBooks unified application theme (light + dark).
///
/// Builds on the existing [ApexColors] extension.  Add this theme to the
/// application via [ThemeData] in the [MaterialApp] builder.
library;

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Builds the full [ThemeData] for light or dark mode.
///
/// Usage:
/// ```dart
/// MaterialApp(
///   theme: buildApexTheme(Brightness.light),
///   darkTheme: buildApexTheme(Brightness.dark),
/// )
/// ```
ThemeData buildApexTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;

  // ── Core palette ─────────────────────────────────────────────────────────
  final colorScheme = isLight
      ? const ColorScheme.light(
          primary: Color(0xFF1A56DB),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFE1EFFE),
          secondary: Color(0xFF6B7280),
          error: Color(0xFFDC2626),
          errorContainer: Color(0xFFFEE2E2),
          surface: Colors.white,
          surfaceContainerHighest: Color(0xFFF3F4F6),
          outline: Color(0xFFD1D5DB),
          outlineVariant: Color(0xFFE5E7EB),
        )
      : const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF1E3A5F),
          secondary: Color(0xFF9CA3AF),
          error: Color(0xFFEF4444),
          errorContainer: Color(0xFF450A0A),
          surface: Color(0xFF111827),
          surfaceContainerHighest: Color(0xFF1F2937),
          outline: Color(0xFF4B5563),
          outlineVariant: Color(0xFF374151),
        );

  // ── Typography ──────────────────────────────────────────────────────────
  final textTheme = isLight ? _lightTextTheme : _darkTextTheme;

  // ── App-specific colors extension ────────────────────────────────────────
  final apexColors = isLight ? _lightApexColors : _darkApexColors;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    extensions: [apexColors],
    // ── Component themes ────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}

// ── ApexColors instances ─────────────────────────────────────────────────────

const _lightApexColors = ApexColors(
  primary: Color(0xFF1A56DB),
  primaryContainer: Color(0xFFE1EFFE),
  onPrimary: Color(0xFFFFFFFF),
  accent: Color(0xFF1A56DB),
  success: Color(0xFF059669),
  warning: Color(0xFFD97706),
  danger: Color(0xFFDC2626),
  info: Color(0xFF2563EB),
  surface: Color(0xFFFFFFFF),
  surfaceRaised: Color(0xFFFFFFFF),
  surfaceMuted: Color(0xFFF3F4F6),
  border: Color(0xFFE5E7EB),
  textPrimary: Color(0xFF111827),
  textSecondary: Color(0xFF6B7280),
  textMuted: Color(0xFF9CA3AF),
  skeletonBase: Color(0xFFE5E7EB),
  skeletonHighlight: Color(0xFFF3F4F6),
);

const _darkApexColors = ApexColors(
  primary: Color(0xFF3B82F6),
  primaryContainer: Color(0xFF1E3A5F),
  onPrimary: Color(0xFFFFFFFF),
  accent: Color(0xFF3B82F6),
  success: Color(0xFF34D399),
  warning: Color(0xFFFBBF24),
  danger: Color(0xFFEF4444),
  info: Color(0xFF60A5FA),
  surface: Color(0xFF111827),
  surfaceRaised: Color(0xFF1F2937),
  surfaceMuted: Color(0xFF1F2937),
  border: Color(0xFF374151),
  textPrimary: Color(0xFFF9FAFB),
  textSecondary: Color(0xFFD1D5DB),
  textMuted: Color(0xFF9CA3AF),
  skeletonBase: Color(0xFF374151),
  skeletonHighlight: Color(0xFF4B5563),
);

// ── Text themes ──────────────────────────────────────────────────────────────

const _lightTextTheme = TextTheme(
  displayLarge: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  ),
  displayMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
  ),
  headlineLarge: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
  ),
  headlineMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  ),
  headlineSmall: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  ),
  titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
  titleMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  ),
  titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
  bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5),
  bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5),
  bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
  ),
);

const _darkTextTheme = TextTheme(
  displayLarge: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    color: Color(0xFFF9FAFB),
  ),
  displayMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: Color(0xFFF9FAFB),
  ),
  headlineLarge: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: Color(0xFFF9FAFB),
  ),
  headlineMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: Color(0xFFF9FAFB),
  ),
  headlineSmall: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: Color(0xFFF9FAFB),
  ),
  titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
  titleMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  ),
  titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
  bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5),
  bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5),
  bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
  ),
);
