import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/states.dart';
import '../../sales/presentation/invoice_form_screen.dart';
import 'dashboard_controller.dart';
import '../models/dashboard_models.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardProvider.notifier).load());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ref.read(dashboardProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
        child: Scrollbar(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              ResponsiveLayout.isMobile(context) ? 12 : 28,
              24,
              ResponsiveLayout.isMobile(context) ? 12 : 28,
              40,
            ),
            itemCount: 3,
            itemBuilder: (context, index) {
              switch (index) {
                case 0:
                  return _header(context, colors, now, state.refreshing);
                case 1:
                  return Column(
                    children: [
                      const SizedBox(height: 24),
                      state.kpis.when(
                        loading: () => _kpiSkeleton(colors),
                        error: (e, _) => _errorCard(
                          colors,
                          'Could not load KPIs',
                          () => ref.read(dashboardProvider.notifier).refresh(),
                        ),
                        data: (data) => _kpiGrid(context, data, state, colors, fmt),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                case 2:
                  return LayoutBuilder(
                    builder: (context, c) {
                      final twoCol = c.maxWidth >= 940;
                      final chart = _chartCard(state, colors, fmt);
                      final alerts = _alertsCard(state, colors, fmt);
                      if (!twoCol) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            children: [chart, const SizedBox(height: 20), alerts],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 3, child: chart),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: alerts),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                default:
                  return const SizedBox.shrink();
              }
            },
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(
    BuildContext context,
    ApexColors colors,
    DateTime now,
    bool refreshing,
  ) {
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Overview',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (refreshing)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: LoadingSpinner(size: 16),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${_months[now.month - 1]} ${now.day}, ${now.year}  ·  Live financials',
                style: TextStyle(fontSize: 13, color: colors.textMuted),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textSecondary,
            side: BorderSide(color: colors.border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const InvoiceFormScreen())),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New Invoice'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
      ],
    );
  }

  // ── KPI grid ────────────────────────────────────────────────────────────
  Widget _kpiGrid(
    BuildContext context,
    DashboardKpis d,
    DashboardState state,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final gst = state.metrics.whenOrNull(data: (m) => m.gstTotal);
    final cards = <Widget>[
      _KpiCard(
        label: 'Receivables',
        value: d.outstanding,
        icon: Icons.account_balance_wallet_rounded,
        tone: colors.primary,
        colors: colors,
        fmt: fmt,
        footer: d.overdue > 0
            ? '${fmt.currency(d.overdue)} overdue'
            : 'All current',
        footerTone: d.overdue > 0 ? colors.danger : colors.success,
      ),
      _KpiCard(
        label: 'Payables',
        value: d.totalExpenses,
        icon: Icons.request_quote_rounded,
        tone: colors.warning,
        colors: colors,
        fmt: fmt,
        footer: 'Owed to vendors',
      ),
      _KpiCard(
        label: 'Net Profit',
        value: d.netProfit,
        icon: d.netProfit >= 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        tone: d.netProfit >= 0 ? colors.success : colors.danger,
        colors: colors,
        fmt: fmt,
        footer: 'This period',
        emphasize: true,
      ),
      _KpiCard(
        label: 'Sales',
        value: d.totalInvoiced,
        icon: Icons.receipt_long_rounded,
        tone: colors.info,
        colors: colors,
        fmt: fmt,
        footer: 'Invoiced',
      ),
      _KpiCard(
        label: 'Collected',
        value: d.totalCollected,
        icon: Icons.payments_rounded,
        tone: colors.success,
        colors: colors,
        fmt: fmt,
        footer: 'Payments in',
      ),
      if (gst != null)
        _KpiCard(
          label: 'GST Liability',
          value: gst,
          icon: Icons.account_balance_rounded,
          tone: colors.warning,
          colors: colors,
          fmt: fmt,
          footer: 'Payable to govt.',
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1180
            ? (cards.length >= 6 ? 6 : cards.length)
            : c.maxWidth >= 860
            ? 3
            : c.maxWidth >= 560
            ? 2
            : 1;
        const gap = 16.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((e) => SizedBox(width: w, child: e)).toList(),
        );
      },
    );
  }

  Widget _kpiSkeleton(ApexColors colors) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 1180
          ? 6
          : c.maxWidth >= 860
          ? 3
          : 2;
      const gap = 16.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(
          cols,
          (_) => SizedBox(
            width: w,
            height: 116,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(ApexRadius.lg),
                border: Border.all(color: colors.border),
              ),
            ),
          ),
        ),
      );
    },
  );

  // ── Chart ────────────────────────────────────────────────────────────────
  Widget _chartCard(
    DashboardState state,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return _Panel(
      colors: colors,
      child: state.revenueTrend.when(
        loading: () =>
            const SizedBox(height: 240, child: Center(child: LoadingSpinner())),
        error: (_, _) =>
            const SizedBox(height: 240, child: Center(child: Text('—'))),
        data: (revenue) {
          final expense =
              state.expenseTrend.whenOrNull(data: (d) => d) ?? <TrendPoint>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Cash Flow',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _legendDot(colors.success, 'Revenue'),
                  const SizedBox(width: 16),
                  _legendDot(colors.danger, 'Expense'),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Monthly revenue against expenses',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
              const SizedBox(height: 20),
              if (revenue.isEmpty && expense.isEmpty)
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'No trend data yet',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                )
              else
                RepaintBoundary(
                  child: SizedBox(
                    height: 220,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TrendChartPainter(
                        _buildTrend(revenue, expense),
                        colors,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  _TrendData _buildTrend(List<TrendPoint> revenue, List<TrendPoint> expense) {
    final allMonths = <String>{
      ...revenue.map((p) => p.label),
      ...expense.map((p) => p.label),
    };
    final sorted = allMonths.toList()..sort((a, b) => a.compareTo(b));
    final revMap = {for (final p in revenue) p.label: p.total};
    final expMap = {for (final p in expense) p.label: p.total};
    final maxVal = [
      if (revenue.isNotEmpty) revenue.map((p) => p.total).reduce(math.max),
      if (expense.isNotEmpty) expense.map((p) => p.total).reduce(math.max),
    ].fold(0.0, (a, b) => a > b ? a : b);
    return _TrendData(sorted, revMap, expMap, maxVal > 0 ? maxVal : 1.0);
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  // ── Alerts ───────────────────────────────────────────────────────────────
  Widget _alertsCard(
    DashboardState state,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return _Panel(
      colors: colors,
      child: state.overdueAlerts.when(
        loading: () =>
            const SizedBox(height: 240, child: Center(child: LoadingSpinner())),
        error: (_, _) =>
            const SizedBox(height: 240, child: Center(child: Text('—'))),
        data: (res) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Overdue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (res.alerts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(ApexRadius.pill),
                      ),
                      child: Text(
                        '${res.count}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.danger,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    fmt.currency(res.totalOverdueAmount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (res.alerts.isEmpty)
                SizedBox(
                  height: 160,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 36,
                          color: colors.success.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No overdue invoices',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...res.alerts.take(6).map((a) => _alertRow(a, colors, fmt)),
            ],
          );
        },
      ),
    );
  }

  Widget _alertRow(OverdueAlert a, ApexColors colors, NumberFormatter fmt) {
    final tone = a.severity == 'critical'
        ? colors.danger
        : a.severity == 'high'
        ? colors.warning
        : colors.info;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(ApexRadius.sm),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.contactName.isEmpty ? a.invoiceNumber : a.contactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${a.invoiceNumber} · ${a.daysOverdue}d overdue',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            fmt.currency(a.balance),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ApexColors colors, String msg, VoidCallback onRetry) =>
      _Panel(
        colors: colors,
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.danger, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: TextStyle(color: colors.textPrimary)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

// ── Reusable premium panel ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel({required this.colors, required this.child});
  final ApexColors colors;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: colors.surfaceRaised,
      borderRadius: BorderRadius.circular(ApexRadius.lg),
      border: Border.all(color: colors.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

// ── Premium KPI card ────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    required this.colors,
    required this.fmt,
    this.footer,
    this.footerTone,
    this.emphasize = false,
  });
  final String label;
  final double value;
  final IconData icon;
  final Color tone;
  final ApexColors colors;
  final NumberFormatter fmt;
  final String? footer;
  final Color? footerTone;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(
          color: emphasize ? tone.withValues(alpha: 0.4) : colors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
                child: Icon(icon, size: 18, color: tone),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmt.currency(value),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 6),
            Text(
              footer!,
              style: TextStyle(
                fontSize: 11,
                color: footerTone ?? colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chart data + painter ────────────────────────────────────────────────────
class _TrendData {
  _TrendData(this.labels, this.revenue, this.expense, this.scale);
  final List<String> labels;
  final Map<String, double> revenue;
  final Map<String, double> expense;
  final double scale;
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter(this.data, this.colors);
  final _TrendData data;
  final ApexColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final labels = data.labels;
    if (labels.isEmpty) return;
    const bottomPad = 22.0;
    final chartH = size.height - bottomPad;

    // Horizontal gridlines
    final grid = Paint()
      ..color = colors.border
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final y = chartH - chartH * g / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final slot = size.width / labels.length;
    final barW = math.min(18.0, slot / 3);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      final center = slot * i + slot / 2;
      final rev = (data.revenue[label] ?? 0) / data.scale * chartH;
      final exp = (data.expense[label] ?? 0) / data.scale * chartH;
      paint.color = colors.success;
      if (rev > 0)
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(center - barW - 2, chartH - rev, barW, rev),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          paint,
        );
      paint.color = colors.danger;
      if (exp > 0)
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(center + 2, chartH - exp, barW, exp),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          paint,
        );

      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: label.split(' ')[0],
          style: TextStyle(fontSize: 10, color: colors.textMuted),
        ),
      )..layout();
      tp.paint(canvas, Offset(center - tp.width / 2, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter old) => old.data != data;
}
