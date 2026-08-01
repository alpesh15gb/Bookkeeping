/// Reusable KPI card component with icon, value, label, trend, and hover state.
///
/// Extracted from [DashboardScreen] — used on the dashboard and any summary
/// screen that displays key metrics.
library;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';
import '../../widgets/monetary_text.dart';

/// Visual emphasis level for the KPI card.
enum KpiEmphasis { normal, high }

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
  final double value;
  final IconData icon;
  final Color tone;
  final String? valuePrefix;
  final String? footer;
  final Color? footerTone;
  final KpiEmphasis emphasis;
  final VoidCallback? onTap;
  final double? trend; // positive = up, negative = down
  final String? trendLabel;
}

/// A single KPI card with icon, formatted value, label, optional footer,
/// hover elevation, and click handler.
class ApexKpiCard extends StatefulWidget {
  const ApexKpiCard({super.key, required this.metric});

  final KpiMetric metric;

  @override
  State<ApexKpiCard> createState() => _ApexKpiCardState();
}

class _ApexKpiCardState extends State<ApexKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    final colors = apexColors(context);
    final mobile = ResponsiveLayout.isMobile(context);
    // ignore: unused_local_variable
    final fmt = NumberFormatService._default;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: m.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.all(mobile ? 13 : 18),
        transform: _hovered && m.onTap != null
            ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0, 1))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(
            color: _hovered && m.onTap != null
                ? m.tone.withValues(alpha: 0.5)
                : m.emphasis == KpiEmphasis.high
                ? m.tone.withValues(alpha: 0.4)
                : colors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: _hovered && m.onTap != null ? 0.06 : 0.03,
              ),
              blurRadius: _hovered && m.onTap != null ? 14 : 10,
              offset: Offset(0, _hovered && m.onTap != null ? 6 : 3),
            ),
          ],
        ),
        child: InkWell(
          onTap: m.onTap,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: m.tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(ApexRadius.sm),
                    ),
                    child: Icon(m.icon, size: 18, color: m.tone),
                  ),
                  const Spacer(),
                  if (m.trend != null)
                    _trendBadge(m.trend!, m.trendLabel, colors),
                ],
              ),
              SizedBox(height: mobile ? 10 : 14),
              // Label
              Text(
                m.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              // Value
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MonetaryText(
                  value: '${m.valuePrefix ?? ''}${_formatValue(m.value)}',
                  fontSize: mobile ? 18 : 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              // Footer
              if (m.footer != null) ...[
                const SizedBox(height: 6),
                Text(
                  m.footer!,
                  style: TextStyle(
                    fontSize: 11,
                    color: m.footerTone ?? colors.textSecondary,
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

  Widget _trendBadge(double trend, String? label, ApexColors colors) {
    final up = trend >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (up ? colors.success : colors.danger).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ApexRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 12,
            color: up ? colors.success : colors.danger,
          ),
          const SizedBox(width: 2),
          Text(
            label ?? '${trend.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: up ? colors.success : colors.danger,
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

// Temporary — will be replaced by the proper NumberFormatter
class NumberFormatService {
  static final NumberFormatService _default = NumberFormatService._();
  NumberFormatService._();
  String currency(double v) => '₹${_formatValue(v)}';
  String _formatValue(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

/// Skeleton loader matching [ApexKpiCard] layout.
class KpiCardSkeleton extends StatelessWidget {
  const KpiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.skeletonBase,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.skeletonHighlight,
              borderRadius: BorderRadius.circular(ApexRadius.sm),
            ),
          ),
          const SizedBox(height: 14),
          Container(width: 80, height: 12, color: colors.skeletonHighlight),
          const SizedBox(height: 6),
          Container(width: 120, height: 24, color: colors.skeletonHighlight),
          const SizedBox(height: 8),
          Container(width: 90, height: 11, color: colors.skeletonHighlight),
        ],
      ),
    );
  }
}
