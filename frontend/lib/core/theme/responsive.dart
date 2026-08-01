/// Centralized responsive breakpoint system for ApexBooks.
///
/// Usage:
/// ```dart
/// final resp = ResponsiveLayout.of(context);
/// if (resp.isMobile) // < 600
/// if (resp.isTablet) // 600–1024
/// if (resp.isDesktop) // > 1024
/// ```
///
/// Always prefer this over ad-hoc `LayoutBuilder` or `MediaQuery` calls
/// so breakpoints stay consistent across every screen.
library;

import 'package:flutter/material.dart';

/// Breakpoint thresholds (logical pixels).
class AppBreakpoints {
  AppBreakpoints._();
  static const double mobile = 600;
  static const double tablet = 1024;
}

/// Screen size classification.
enum ScreenSize {
  mobile,
  tablet,
  desktop;

  bool get isMobile => this == ScreenSize.mobile;
  bool get isTablet => this == ScreenSize.tablet;
  bool get isDesktop => this == ScreenSize.desktop;
}

/// Provides the current [ScreenSize] and a few convenience helpers.
/// Place an [InheritedResponsive] higher up (the [ResponsiveLayout] widget
/// does this automatically) and read it via `ResponsiveLayout.of(context)`.
class InheritedResponsive extends InheritedWidget {
  const InheritedResponsive({
    super.key,
    required this.size,
    required this.screenSize,
    required super.child,
  });

  /// The raw width from [LayoutBuilder] / [MediaQuery].
  final double size;

  /// The classified screen size.
  final ScreenSize screenSize;

  bool get isMobile => screenSize.isMobile;
  bool get isTablet => screenSize.isTablet;
  bool get isDesktop => screenSize.isDesktop;

  @override
  bool updateShouldNotify(covariant InheritedResponsive oldWidget) =>
      size != oldWidget.size;
}

/// A convenience widget that builds a responsive subtree based on screen size.
///
/// The three builders mirror the mobile / tablet / desktop breakpoints.
/// When a builder is omitted the [fallback] (default: `SizedBox.shrink()`) is
/// used, so you can customise only the sizes you care about.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    this.mobile,
    this.tablet,
    this.desktop,
    this.fallback,
    this.child, // used when none of mobile/tablet/desktop are provided
  });

  /// Builder for screens < [AppBreakpoints.mobile].
  final Widget? mobile;

  /// Builder for screens >= [AppBreakpoints.mobile] and < [AppBreakpoints.tablet].
  final Widget? tablet;

  /// Builder for screens >= [AppBreakpoints.tablet].
  final Widget? desktop;

  /// Fallback widget when the current size doesn't match any builder.
  final Widget? fallback;

  /// Optional child that will always be wrapped in the responsive context.
  final Widget? child;

  /// Shorthand to read the current responsive info from the widget tree.
  /// Returns a desktop-sized default when called outside [ResponsiveLayout].
  static InheritedResponsive of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<InheritedResponsive>();
    if (inherited != null) return inherited;
    // Safe fallback when no ResponsiveLayout ancestor is present (e.g. tests).
    return const InheritedResponsive(
      size: 1440,
      screenSize: ScreenSize.desktop,
      child: SizedBox.shrink(),
    );
  }

  static ScreenSize screenSizeOf(BuildContext context) =>
      of(context).screenSize;
  static bool isMobile(BuildContext context) => of(context).isMobile;
  static bool isTablet(BuildContext context) => of(context).isTablet;
  static bool isDesktop(BuildContext context) => of(context).isDesktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final screenSize = _classify(width);

        Widget? body;
        if (screenSize.isMobile && mobile != null) {
          body = mobile;
        } else if (screenSize.isTablet && tablet != null) {
          body = tablet;
        } else if (screenSize.isDesktop && desktop != null) {
          body = desktop;
        } else if (child != null) {
          body = child;
        } else {
          body = fallback ?? const SizedBox.shrink();
        }

        return InheritedResponsive(
          size: width,
          screenSize: screenSize,
          child: body!,
        );
      },
    );
  }

  static ScreenSize _classify(double width) {
    if (width < AppBreakpoints.mobile) return ScreenSize.mobile;
    if (width < AppBreakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }
}
