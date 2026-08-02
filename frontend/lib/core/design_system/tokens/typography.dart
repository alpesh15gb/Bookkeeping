/// ApexBooks Design Tokens — Typography Scale
///
/// Consistent typography scale for all text elements.
/// Based on Material 3 type scale with adjustments for accounting data density.
library;

import 'package:flutter/material.dart';

/// Typography configuration for the ApexBooks design system.
class ApexTypography {
  // ───── Font Families ─────
  static const String fontFamily = 'Inter';
  static const String fontFamilyMono = 'JetBrains Mono';

  // ───── Display (Large headlines) ─────
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 57,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.12,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 45,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1.16,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.22,
  );

  // ───── Headline (Screen titles) ─────
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.29,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.33,
  );

  // ───── Title (Section headers) ─────
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.27,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
    height: 1.50,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  // ───── Body (Main content) ─────
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.50,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.43,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.33,
  );

  // ───── Label (UI elements) ─────
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.45,
  );

  // ───── Monospace (Numbers, codes) ─────
  static const TextStyle monoLarge = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.50,
  );

  static const TextStyle monoMedium = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.43,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.33,
  );

  // ───── Custom Accounting Styles ─────

  /// Large monetary amount (totals, grand totals)
  static const TextStyle monetaryLarge = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Medium monetary amount (line totals, subtotals)
  static const TextStyle monetaryMedium = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.25,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Small monetary amount (table cells)
  static const TextStyle monetarySmall = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Table header text
  static const TextStyle tableHeader = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.33,
    color: null,
  );

  /// Table cell text
  static const TextStyle tableCell = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.38,
    color: null,
  );

  /// Table cell monetary
  static const TextStyle tableCellMonetary = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
    color: null,
  );

  /// KPI value
  static const TextStyle kpiValue = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// KPI label
  static const TextStyle kpiLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.33,
  );
}

/// Extension to easily apply color to text styles.
extension TextStyleColor on TextStyle {
  TextStyle withColor(Color color) => copyWith(color: color);
}