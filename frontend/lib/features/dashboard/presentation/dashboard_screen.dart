import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
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
              ResponsiveLayout.isMobile(context) ? 16 : 24,
              ResponsiveLayout.isMobile(context) ? 12 : 28,
              40,
            ),
            itemCount: 4,
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
                        data: (data) =>
                            _kpiGrid(context, data, state, colors, fmt),
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
                            children: [
                              chart,
                              const SizedBox(height: 20),
                              alerts,
                            ],
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
                case 3:
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _gstSummaryCard(state, colors, fmt, now),
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
    final mobile = ResponsiveLayout.isMobile(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              'Overview',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
        ),
      ],
    );
    final refresh = OutlinedButton.icon(
      onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text(mobile ? 'Reload' : 'Refresh'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textSecondary,
        side: BorderSide(color: colors.border),
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 12 : 16,
          vertical: 14,
        ),
      ),
    );
    final create = FilledButton.icon(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const InvoiceFormScreen())),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('New Invoice'),
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 14 : 18,
          vertical: 14,
        ),
      ),
    );
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: refresh),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: create),
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: heading),
        refresh,
        const SizedBox(width: 12),
        create,
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
            : 2;
        final gap = c.maxWidth < 560 ? 10.0 : 16.0;
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
          (_) => SizedBox(width: w, child: const KpiCardSkeleton()),
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
        loading: () => ShimmerSkeleton(
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              color: colors.skeletonBase,
              borderRadius: BorderRadius.circular(ApexRadius.lg),
            ),
          ),
        ),
        error: (_, _) =>
            const SizedBox(height: 240, child: Center(child: Text('—'))),
        data: (revenue) {
          final expense =
              state.expenseTrend.whenOrNull(data: (d) => d) ?? <TrendPoint>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) => c.maxWidth < 420
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cash Flow',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 14,
                            children: [
                              _legendDot(colors.success, 'Revenue'),
                              _legendDot(colors.danger, 'Expense'),
                            ],
                          ),
                        ],
                      )
                    : Row(
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
                SizedBox(
                  height: 220,
                  child: _buildFlChart(revenue, expense, colors, fmt),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFlChart(
    List<TrendPoint> revenue,
    List<TrendPoint> expense,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final allMonths = <String>{
      ...revenue.map((p) => p.label),
      ...expense.map((p) => p.label),
    };
    final sorted = allMonths.toList()..sort((a, b) => a.compareTo(b));
    final revMap = {for (final p in revenue) p.label: p.total};
    final expMap = {for (final p in expense) p.label: p.total};

    final maxY = [
      ...revenue.map((p) => p.total),
      ...expense.map((p) => p.total),
    ].fold(0.0, (a, b) => a > b ? a : b);

    // If no data at all, show empty state
    if (sorted.isEmpty) {
      return Center(
        child: Text(
          'No trend data yet',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxY == 0 ? 1 : maxY) * 1.15,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final value = rod.toY;
              final seriesLabel = rodIndex == 0 ? 'Revenue' : 'Expense';
              return BarTooltipItem(
                '$seriesLabel\n${fmt.currency(value)}',
                TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  fmt.quantity(value),
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= sorted.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    sorted[index].split(' ')[0],
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY == 0 ? 1 : maxY) / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: colors.border, strokeWidth: 1);
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(sorted.length, (i) {
          final label = sorted[i];
          final revValue = revMap[label] ?? 0;
          final expValue = expMap[label] ?? 0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: revValue,
                color: colors.success,
                width: 14,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              BarChartRodData(
                toY: expValue,
                color: colors.danger,
                width: 14,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          );
        }),
      ),
      swapAnimationDuration: const Duration(milliseconds: 600),
      swapAnimationCurve: Curves.easeOutCubic,
    );
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
        loading: () => ShimmerSkeleton(
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              color: colors.skeletonBase,
              borderRadius: BorderRadius.circular(ApexRadius.lg),
            ),
          ),
        ),
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

  // ── GST Summary ───────────────────────────────────────────────────────────
  Widget _gstSummaryCard(
    DashboardState state,
    ApexColors colors,
    NumberFormatter fmt,
    DateTime now,
  ) {
    return state.metrics.when(
      loading: () => _Panel(
        colors: colors,
        child: ShimmerSkeleton(
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: colors.skeletonBase,
              borderRadius: BorderRadius.circular(ApexRadius.lg),
            ),
          ),
        ),
      ),
      error: (e, _) => _Panel(
        colors: colors,
        child: _errorCard(
          colors,
          'Could not load GST summary',
          () => ref.read(dashboardProvider.notifier).refresh(),
        ),
      ),
      data: (m) {
        final cgst = m.cgstTotal;
        final sgst = m.sgstTotal;
        final igst = m.igstTotal;
        final totalOutput = cgst + sgst + igst;
        final netPayable =
            totalOutput; // Net of ITC; backend provides full calc
        return _Panel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 430;
                  final title = Text(
                    'GST Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  );
                  final payable = Text(
                    'Net Payable: ${fmt.currency(netPayable)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  );
                  return narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, const SizedBox(height: 4), payable],
                        )
                      : Row(children: [title, const Spacer(), payable]);
                },
              ),
              const SizedBox(height: 4),
              Text(
                '${_months[now.month - 1]} ${now.year}  ·  Output GST',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final mobile = c.maxWidth < 560;
                  final items = <Widget>[
                    _gstItem('CGST', fmt.currency(cgst), colors),
                    _gstItem('SGST', fmt.currency(sgst), colors),
                    if (igst > 0) _gstItem('IGST', fmt.currency(igst), colors),
                    _gstItem(
                      'Total',
                      fmt.currency(totalOutput),
                      colors,
                      emphasize: true,
                    ),
                  ];
                  if (!mobile) {
                    return Row(
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(child: items[i]),
                        ],
                      ],
                    );
                  }
                  const gap = 10.0;
                  final width = (c.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: items
                        .map((item) => SizedBox(width: width, child: item))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gstItem(
    String label,
    String value,
    ApexColors colors, {
    bool emphasize = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(ApexRadius.md),
        border: emphasize
            ? Border.all(color: colors.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          MonetaryText(
            value: value,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: emphasize ? colors.primary : colors.textPrimary,
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
  Widget build(BuildContext context) => ApexCard(
    padding: EdgeInsets.all(ResponsiveLayout.isMobile(context) ? 14 : 20),
    child: child,
  );
}

// ── Premium KPI card ────────────────────────────────────────────────────────
class _KpiCard extends StatefulWidget {
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
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mobile = ResponsiveLayout.isMobile(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.all(mobile ? 13 : 18),
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -2.0))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(
            color: _hovered
                ? widget.tone.withValues(alpha: 0.5)
                : widget.emphasize
                ? widget.tone.withValues(alpha: 0.4)
                : widget.colors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.06 : 0.03),
              blurRadius: _hovered ? 14 : 10,
              offset: Offset(0, _hovered ? 6 : 3),
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
                    color: widget.tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ApexRadius.sm),
                  ),
                  child: Icon(widget.icon, size: 18, color: widget.tone),
                ),
                const Spacer(),
              ],
            ),
            SizedBox(height: mobile ? 10 : 14),
            Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                color: widget.colors.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MonetaryText(
                value: widget.fmt.currency(widget.value),
                fontSize: mobile ? 18 : 22,
                fontWeight: FontWeight.w700,
                color: widget.colors.textPrimary,
              ),
            ),
            if (widget.footer != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.footer!,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.footerTone ?? widget.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
