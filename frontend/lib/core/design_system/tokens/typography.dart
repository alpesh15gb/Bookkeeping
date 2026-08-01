/// ApexBooks Design Tokens — Typography
///
/// Semantic text styles for every UI context. Always use these helpers or
/// the Theme's textTheme values rather than ad-hoc TextStyle constructors.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale presets.
class ApexTextStyle {
  ApexTextStyle._();

  // ── Display (Instrument Sans) ────────────────────────────────────────────

  static TextStyle display({
    double size = 32,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => GoogleFonts.instrumentSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
  );

  // ── Body / UI (Inter) ────────────────────────────────────────────────────

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color);

  // ── Financial / Data (JetBrains Mono with tabular figures) ───────────────

  static TextStyle monetary({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Predefined semantic text styles matching the design spec.
class ApexTextStyles {
  ApexTextStyles._();

  // Page / section headers
  static TextStyle pageTitle = GoogleFonts.instrumentSans(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  static TextStyle sectionTitle = GoogleFonts.instrumentSans(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );
  static TextStyle cardTitle = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // Data
  static TextStyle kpiValue = GoogleFonts.jetBrainsMono(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontFeatures: [const FontFeature.tabularFigures()],
  );
  static TextStyle tableAmount = GoogleFonts.jetBrainsMono(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFeatures: [const FontFeature.tabularFigures()],
  );
  static TextStyle tableLabel = GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  // Labels
  static TextStyle labelSmall = GoogleFonts.inter(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );
  static TextStyle meta = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
}
