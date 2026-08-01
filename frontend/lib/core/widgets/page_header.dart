/// A consistent page scaffold with an optional title, subtitle and trailing
/// action, used as the top of most screens.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/responsive.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.padding,
  });

  /// The effective padding. When [padding] is null a context-aware default is
  /// computed once in [build] so it responds to the current screen size.
  EdgeInsetsGeometry _effectivePadding(BuildContext context) {
    return padding ??
        EdgeInsets.fromLTRB(
          ResponsiveLayout.isMobile(context) ? 12 : 24,
          20,
          ResponsiveLayout.isMobile(context) ? 12 : 24,
          16,
        );
  }

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final effectivePadding = _effectivePadding(context);
    final mobile = ResponsiveLayout.isMobile(context);
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
            alignment: mobile ? WrapAlignment.start : WrapAlignment.end,
            children: actions!,
          );
    return Padding(
      padding: effectivePadding,
      child: mobile
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

/// A contained card surface used for content panels.
class ApexCard extends StatefulWidget {
  const ApexCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  State<ApexCard> createState() => _ApexCardState();
}

class _ApexCardState extends State<ApexCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isInteractive = widget.onTap != null;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      transform: (isInteractive && _hovered)
          ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(
          color: _hovered ? colors.primary.withValues(alpha: 0.5) : colors.border,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _hovered ? 0.05 : 0.02),
            blurRadius: _hovered ? 12 : 8,
            offset: Offset(0, _hovered ? 5 : 3),
          ),
        ],
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (widget.onTap != null) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      );
    }
    return card;
  }
}
