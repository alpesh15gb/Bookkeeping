/// ApexBooks card component.
library;

import 'package:flutter/material.dart';
import '../tokens/app_spacing.dart';

enum ApexCardVariant { standard, highlighted, danger, interactive }

class ApexCard extends StatefulWidget {
  const ApexCard({
    super.key,
    this.variant = ApexCardVariant.standard,
    this.padding = AppSpacing.lg,
    this.child,
    this.onTap,
    this.margin,
  });

  final ApexCardVariant variant;
  final double padding;
  final Widget? child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  State<ApexCard> createState() => _ApexCardState();
}

class _ApexCardState extends State<ApexCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isInteractive = widget.onTap != null || widget.variant == ApexCardVariant.interactive;

    final borderColor = switch (widget.variant) {
      ApexCardVariant.highlighted => colors.primary,
      ApexCardVariant.danger => colors.error,
      _ => _hovered ? colors.primary.withValues(alpha: 0.5) : colors.outlineVariant,
    };
    final bgColor = switch (widget.variant) {
      ApexCardVariant.danger => colors.errorContainer.withValues(alpha: 0.2),
      _ => colors.surface,
    };

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      margin: widget.margin ?? EdgeInsets.zero,
      padding: EdgeInsets.all(widget.padding),
      transform: (isInteractive && _hovered)
          ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: widget.variant != ApexCardVariant.standard
            ? Border.all(color: borderColor, width: 1.5)
            : Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _hovered ? 0.05 : 0.02),
            blurRadius: _hovered ? 12 : 8,
            offset: Offset(0, _hovered ? 4 : 2),
          ),
        ],
      ),
      child: widget.child,
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

class ApexKpiCard extends StatelessWidget {
  const ApexKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trend,
    this.trendLabel,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final double? trend;
  final String? trendLabel;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;

    return ApexCard(
      variant: ApexCardVariant.interactive,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          if (trend != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Icon(
                  trend! >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 14,
                  color: trend! >= 0 ? Colors.green : Colors.red,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  '${trend!.abs().toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: trend! >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                if (trendLabel != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(trendLabel!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
