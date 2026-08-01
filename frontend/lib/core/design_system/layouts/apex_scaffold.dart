/// Responsive page scaffold — consistent layout for every screen.
///
/// Provides the standard ApexBooks page structure:
///   PageHeader (title + subtitle + actions)
///   FilterBar (optional)
///   Content area (scrollable, centered, max-width constrained)
///
/// Handles responsive padding and layout automatically.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';

/// Standard page layout with optional header, filter bar, and scrollable content.
class ApexScaffold extends StatelessWidget {
  const ApexScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.filterBar,
    this.children,
    this.floatingActionButton,
    this.backgroundColor,
    this.maxContentWidth = 1200,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? filterBar;
  final List<Widget>? children;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final double maxContentWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: backgroundColor ?? colors.surfaceMuted,
      floatingActionButton: floatingActionButton,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page header
          _PageHeader(
            title: title,
            subtitle: subtitle,
            actions: actions,
            isMobile: isMobile,
          ),
          // Filter bar
          if (filterBar != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 12 : 24,
                0,
                isMobile ? 12 : 24,
                8,
              ),
              child: filterBar!,
            ),
          // Scrollable content
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: _responsivePadding(
                  context,
                  child: ListView(
                    padding:
                        padding ??
                        EdgeInsets.only(
                          left: isMobile ? 12 : 24,
                          right: isMobile ? 12 : 24,
                          top: 0,
                          bottom: 40,
                        ),
                    children: children ?? [],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsivePadding(BuildContext context, {required Widget child}) {
    final isMobile = ResponsiveLayout.isMobile(context);
    if (padding != null) return child;
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: child,
      );
    }
    return child;
  }
}

/// Form scaffold with sticky bottom bar for totals and save action.
class ApexFormScaffold extends StatelessWidget {
  const ApexFormScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.children,
    this.bottomBar,
    this.maxContentWidth = 900,
    this.error,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? children;
  final Widget? bottomBar;
  final double maxContentWidth;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: colors.surfaceRaised,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: colors.textPrimary,
          ),
        ),
        actions: [
          if (!isMobile)
            TextButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Error banner
          if (error != null)
            Container(
              width: double.infinity,
              color: colors.danger.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: colors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: colors.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Scrollable content
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: ListView(
                  padding: EdgeInsets.all(isMobile ? 10 : 16),
                  children: children ?? [],
                ),
              ),
            ),
          ),
          // Bottom bar
          ?bottomBar,
        ],
      ),
    );
  }
}

// ── Private page header ──────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    this.subtitle,
    this.actions,
    required this.isMobile,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: colors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );

    final actionRow = actions == null
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: actions!,
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        20,
        isMobile ? 12 : 24,
        16,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (actionRow != null) ...[
                  const SizedBox(height: 12),
                  actionRow,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                if (actionRow != null) ...[
                  const SizedBox(width: 16),
                  actionRow,
                ],
              ],
            ),
    );
  }
}
