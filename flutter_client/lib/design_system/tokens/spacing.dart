import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double pagePadding = 24;
  static const double sectionGap = 16;
  static const double cardPadding = 16;
  static const double rowPadding = 12;
  static const double kpiGap = 12;
  static const double sidebarWidth = 240;
  static const double sidebarCollapsedWidth = 64;
  static const double topBarHeight = 56;
}

class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 999;
}

class AppShadow {
  AppShadow._();

  static const card = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const elevated = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const alert = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];
}
