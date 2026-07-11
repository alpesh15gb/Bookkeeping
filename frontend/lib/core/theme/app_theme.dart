/// ApexBooks light + dark [ThemeData] builders built on the [ApexColors] tokens.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Builds the ApexBooks light [ThemeData].
ThemeData apexLightTheme() => _buildTheme(lightApexColors, Brightness.light);

/// Builds the ApexBooks dark [ThemeData].
ThemeData apexDarkTheme() => _buildTheme(darkApexColors, Brightness.dark);

ThemeData _buildTheme(ApexColors colors, Brightness brightness) {
  final base = ColorScheme(
    brightness: brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.primaryContainer,
    onPrimaryContainer: colors.primary,
    secondary: colors.accent,
    onSecondary: colors.onPrimary,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    error: colors.danger,
    onError: colors.onPrimary,
  );

  final baseText = GoogleFonts.interTextTheme();
  final textTheme = baseText.copyWith(
    bodyLarge: baseText.bodyLarge?.copyWith(color: colors.textPrimary),
    bodyMedium: baseText.bodyMedium?.copyWith(color: colors.textPrimary),
    bodySmall: baseText.bodySmall?.copyWith(color: colors.textSecondary),
    titleLarge: baseText.titleLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: baseText.titleMedium?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
    labelLarge: baseText.labelLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: base,
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    dividerColor: colors.border,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        side: BorderSide(color: colors.border),
      ),
    ),
    inputDecorationTheme: _inputDecoration(colors),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
        ),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 48),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ApexRadius.md),
        ),
        side: BorderSide(color: colors.border),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceMuted,
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ApexRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ApexRadius.xl),
      ),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      contentTextStyle: GoogleFonts.inter(
        fontSize: 14,
        color: colors.textSecondary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.textPrimary,
      contentTextStyle: GoogleFonts.inter(
        fontSize: 14,
        color: colors.surface,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ApexRadius.md),
      ),
    ),
    extensions: [colors],
  );
}

InputDecorationTheme _inputDecoration(ApexColors colors) {
  return InputDecorationTheme(
    filled: true,
    fillColor: colors.surfaceMuted,
    hintStyle: GoogleFonts.inter(color: colors.textMuted, fontSize: 14),
    labelStyle: GoogleFonts.inter(color: colors.textSecondary, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      borderSide: BorderSide(color: colors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      borderSide: BorderSide(color: colors.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      borderSide: BorderSide(color: colors.danger, width: 1.5),
    ),
  );
}
