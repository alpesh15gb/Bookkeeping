/// ApexBooks light + dark [ThemeData] builders built on the [ApexColors] tokens.
///
/// Font stack per DESIGN.md:
///   Display/Headings → Instrument Sans (weights 500-700)
///   Body/UI          → Inter (weights 400-700)
///   Data/Tables      → JetBrains Mono (with tabular-nums)
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'package:apexbooks/core/design_system/index.dart';

/// Builds the ApexBooks light [ThemeData].
ThemeData apexLightTheme() => _buildTheme(ApexColors.light, Brightness.light);

/// Builds the ApexBooks dark [ThemeData].
ThemeData apexDarkTheme() => _buildTheme(ApexColors.dark, Brightness.dark);

ThemeData _buildTheme(ApexColors colors, Brightness brightness) {
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
  final controlHeight = isDesktop ? 40.0 : 48.0;
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

  // -- Font themes (Google Fonts caches after first use) -------------------
  final bodyText = GoogleFonts.interTextTheme();
  final displayText = GoogleFonts.instrumentSansTextTheme();

  final textTheme = bodyText.copyWith(
    // Display/headings → Instrument Sans
    displayLarge: displayText.displayLarge?.copyWith(color: colors.textPrimary),
    displayMedium: displayText.displayMedium?.copyWith(
      color: colors.textPrimary,
    ),
    displaySmall: displayText.displaySmall?.copyWith(color: colors.textPrimary),
    headlineLarge: displayText.headlineLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineMedium: displayText.headlineMedium?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    headlineSmall: displayText.headlineSmall?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    // Body/UI → Inter
    bodyLarge: bodyText.bodyLarge?.copyWith(color: colors.textPrimary),
    bodyMedium: bodyText.bodyMedium?.copyWith(color: colors.textPrimary),
    bodySmall: bodyText.bodySmall?.copyWith(color: colors.textSecondary),
    titleLarge: bodyText.titleLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: bodyText.titleMedium?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: bodyText.titleSmall?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
    labelLarge: bodyText.labelLarge?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: bodyText.labelSmall?.copyWith(
      color: colors.textSecondary,
      fontWeight: FontWeight.w600,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
    materialTapTargetSize: isDesktop
        ? MaterialTapTargetSize.shrinkWrap
        : MaterialTapTargetSize.padded,
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
      titleTextStyle: GoogleFonts.instrumentSans(
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
        textStyle: GoogleFonts.instrumentSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        minimumSize: Size(0, controlHeight),
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
        textStyle: GoogleFonts.instrumentSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        minimumSize: Size(0, controlHeight),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size.square(isDesktop ? 36 : 44),
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
      titleTextStyle: GoogleFonts.instrumentSans(
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
