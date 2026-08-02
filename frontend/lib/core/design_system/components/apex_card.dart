/// Reusable card component with consistent elevation, padding, and hover states.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';

/// Visual emphasis level for cards.
enum CardElevation { none, low, medium, high }

/// A consistent card wrapper used across all feature screens.
class ApexCard extends StatefulWidget {
  const ApexCard({
    super.key,
    required this.child,
    this.elevation = CardElevation.low,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.border,
    this.color,
    this.borderRadius,
    this.hoverElevation = CardElevation.medium,
  });

  final Widget child;
  final CardElevation elevation;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Border? border;
  final Color? color;
  final BorderRadius? borderRadius;
  final CardElevation hoverElevation;

  @override
  State<ApexCard> createState() => _ApexCardState();
}

class _ApexCardState extends State<ApexCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final effectiveElevation = _hovered && widget.onTap != null
        ? widget.hoverElevation
        : widget.elevation;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? colors.surface,
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        border: widget.border ?? Border.all(color: colors.border, width: 1),
        boxShadow: _shadowFor(effectiveElevation, colors),
      ),
      child: widget.child,
    );

    if (widget.onTap != null) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          child: card,
        ),
      );
    }

    return card;
  }

  List<BoxShadow> _shadowFor(CardElevation elevation, ApexColors colors) {
    switch (elevation) {
      case CardElevation.none:
        return [];
      case CardElevation.low:
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ];
      case CardElevation.medium:
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];
      case CardElevation.high:
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ];
    }
  }
}

/// Specialized card for KPI metrics with icon, value, label, and optional trend.
class ApexKpiCard extends StatefulWidget {
  const ApexKpiCard({
    super.key,
    required this.metric,
    this.onTap,
  });

  final KpiMetric metric;
  final VoidCallback? onTap;

  @override
  State<ApexKpiCard> createState() => _ApexKpiCardState();
}

class _ApexKpiCardState extends State<ApexKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? colors.primary.withValues(alpha: 0.3) : colors.border,
            width: _hovered ? 2 : 1,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon + optional trend
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m.tone,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(m.icon, size: 24, color: colors.onPrimary),
                  ),
                  const Spacer(),
                  if (m.trend != null) _buildTrend(m, colors, textTheme),
                ],
              ),
              const SizedBox(height: 16),

              // Value + label
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.value,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.label,
                    style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),

              // Optional footer
              if (m.footer != null) ...[
                const SizedBox(height: 8),
                Text(
                  m.footer!,
                  style: textTheme.bodySmall?.copyWith(
                    color: m.footerTone ?? colors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrend(KpiMetric m, ApexColors colors, TextTheme textTheme) {
    final isPositive = m.trend!.startsWith('+');
    final trendColor = isPositive ? colors.success : colors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trendColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 12, color: trendColor),
          const SizedBox(width: 4),
          Text(
            m.trend!,
            style: textTheme.labelSmall?.copyWith(color: trendColor, fontWeight: FontWeight.w600),
          ),
          if (m.trendLabel != null) ...[
            const SizedBox(width: 4),
            Text(m.trendLabel!, style: textTheme.labelSmall?.copyWith(color: trendColor)),
          ],
        ],
      ),
    );
  }
}

/// Configuration for a single KPI metric.
class KpiMetric {
  const KpiMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.valuePrefix,
    this.footer,
    this.footerTone,
    this.emphasis = KpiEmphasis.normal,
    this.onTap,
    this.trend,
    this.trendLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final String? valuePrefix;
  final String? footer;
  final Color? footerTone;
  final KpiEmphasis emphasis;
  final VoidCallback? onTap;
  final String? trend;
  final String? trendLabel;
}

/// Visual emphasis level for the KPI card.
enum KpiEmphasis { normal, high }