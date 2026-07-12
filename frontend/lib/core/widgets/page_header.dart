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
    return padding ?? EdgeInsets.fromLTRB(
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
    return Padding(
      padding: effectivePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
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
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions!.map((w) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: w,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// A contained card surface used for content panels.
class ApexCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final card = Card(
      color: colors.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        side: BorderSide(color: colors.border, width: 1.0),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.015),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ApexRadius.lg),
      child: card,
    );
  }
}
