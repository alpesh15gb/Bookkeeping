import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  AppTypography._();

  static TextStyle _base = GoogleFonts.inter();

  static TextStyle displayLarge = _base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static TextStyle displayMedium = _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static TextStyle displaySmall = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w600);
  static TextStyle headlineLarge = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle headlineMedium = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
  static TextStyle headlineSmall = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);
  static TextStyle bodyLarge = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle bodyMedium = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400);
  static TextStyle bodySmall = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400);
  static TextStyle labelLarge = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w500);
  static TextStyle labelMedium = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500);
  static TextStyle labelSmall = _base.copyWith(fontSize: 11, fontWeight: FontWeight.w500);
  static TextStyle amountLarge = _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, fontFeatures: [const FontFeature.tabularFigures()]);
  static TextStyle amountMedium = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: [const FontFeature.tabularFigures()]);
  static TextStyle amountSmall = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: [const FontFeature.tabularFigures()]);
  static TextStyle amountTiny = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, fontFeatures: [const FontFeature.tabularFigures()]);
}
