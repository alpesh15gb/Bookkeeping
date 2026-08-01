/// ApexBooks spacing token system.
///
/// Use these constants instead of raw `double` values for padding, margin,
/// gap, and inset properties.  Exceptions: 1-px borders and dividers.
library;

import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  // Base unit: 4px
  static const double unit = 4;

  static const double xxs = 2; // 2px — micro spacing
  static const double xs = 4; // 4px — tight icon-label gap
  static const double sm = 8; // 8px — compact inset
  static const double md = 12; // 12px — standard inner padding
  static const double lg = 16; // 16px — card padding
  static const double xl = 20; // 20px — section spacing
  static const double xxl = 24; // 24px — page padding
  static const double xxxl = 32; // 32px — screen-level margins
  static const double huge = 40; // 40px — large gaps
  static const double massive = 48; // 48px — section separation
  static const double giant = 64; // 64px — major layout blocks
}

class AppRadius {
  AppRadius._();

  static const double none = 0;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double full = 999;
}

class AppElevation {
  AppElevation._();

  /// Cards, list items
  static const double level1 = 1;

  /// Dropdowns, popovers
  static const double level2 = 2;

  /// FAB, sticky headers
  static const double level3 = 4;

  /// Dialogs, sheets
  static const double level4 = 8;

  /// Modals, drawers
  static const double level5 = 16;
}

class AppBreakpoints {
  AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
  static bool isWide(double width) => width >= wide;
}

class AppDurations {
  AppDurations._();

  static const Duration fastest = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration pageTransition = Duration(milliseconds: 300);

  static const Curve defaultCurve = Curves.easeInOut;
  static const Curve emphasisCurve = Curves.easeOutCubic;
}

class AppOpacity {
  AppOpacity._();

  static const double disabled = 0.38;
  static const double medium = 0.54;
  static const double enabled = 0.87;
  static const double high = 1.0;
  static const double hoverOpacity = 0.08;
  static const double focusOpacity = 0.12;
  static const double pressedOpacity = 0.16;
  static const double scrimOpacity = 0.50;
}
