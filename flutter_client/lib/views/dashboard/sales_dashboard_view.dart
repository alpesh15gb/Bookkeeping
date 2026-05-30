import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/dashboard_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';

class SalesDashboardView extends StatefulWidget {
  const SalesDashboardView({super.key});

  @override
  State<SalesDashboardView> createState() => _SalesDashboardViewState();
}

class _SalesDashboardViewState extends State<SalesDashboardView> {
  int _selectedPeriodIndex = 0; // 0 = 30 Days, 1 = Quarter, 2 = Year

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchDashboard();
    });
  }

  List<dynamic> _filterTrend(List<dynamic> trend, int periodIndex) {
    if (trend.isEmpty) return trend;
    if (periodIndex == 0) {
      return trend.length > 2 ? trend.sublist(trend.length - 2) : trend;
    } else if (periodIndex == 1) {
      return trend.length > 4 ? trend.sublist(trend.length - 4) : trend;
    } else {
      return trend;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();

    if (dashboard.isLoading) {
      return const LoadingState(message: 'Loading dashboard...');
    }
    if (dashboard.errorMessage != null) {
      return ErrorState(
        message: dashboard.errorMessage!,
        onRetry: () => dashboard.fetchDashboard(),
      );
    }

    final hasData = dashboard.revenue > 0 ||
        dashboard.totalExpenses > 0 ||
        dashboard.recentInvoices.isNotEmpty ||
        dashboard.receivables > 0 ||
        dashboard.payables > 0 ||
        dashboard.totalTax > 0;

    final isMobile = AdaptiveLayout.isMobile(context);
    final padding = isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding;
    final crossAxisCount = isMobile ? 2 : 4;

    // Build trend sparkline arrays from real trend data
    final revSpark = dashboard.revenueTrend
        .map((d) => double.tryParse((d['total'] ?? 0).toString()) ?? 0.0)
        .toList();
    final expSpark = dashboard.expenseTrend
        .map((d) => double.tryParse((d['total'] ?? 0).toString()) ?? 0.0)
        .toList();

    if (revSpark.isEmpty) revSpark.addAll([0]);
    if (expSpark.isEmpty) expSpark.addAll([0]);

    final profitSpark = List.generate(
      revSpark.length < expSpark.length ? revSpark.length : expSpark.length,
      (i) => revSpark[i] - expSpark[i],
    );
    if (profitSpark.isEmpty) profitSpark.addAll([0]);

    final taxSpark = revSpark.map((v) => v * 0.18).toList();

    if (!hasData) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        body: ListView(
          padding: padding,
          children: [
            Text('Dashboard', style: AppTextStyles.h1),
            const SizedBox(height: 4),
            Text('Your financial overview at a glance', style: AppTextStyles.bodySmall),
            const SizedBox(height: 32),
            EmptyState(
              icon: Icons.dashboard_rounded,
              title: 'Welcome to Apex Books',
              subtitle: 'Create your first invoice, record an expense, or add a party to get started',
            ),
            const SizedBox(height: 32),
            Text('Quick Actions', style: AppTextStyles.h3),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: isMobile ? 1 : 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isMobile ? 3.8 : 2.5,
              children: [
                _QuickActionCard(
                  label: 'New Invoice',
                  icon: Icons.description_rounded,
                  gradient: const [Color(0xFF0E9384), Color(0xFF0A7569)],
                  onTap: () => _nav(context, const InvoiceFormView(), dashboard),
                ),
                _QuickActionCard(
                  label: 'Add Party',
                  icon: Icons.person_add_rounded,
                  gradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  onTap: () => _navDialog(context, const ContactFormView(), dashboard),
                ),
                _QuickActionCard(
                  label: 'Record Payment',
                  icon: Icons.payments_rounded,
                  gradient: const [Color(0xFF067647), Color(0xFF045835)],
                  onTap: () => _navPayment(context, dashboard),
                ),
                _QuickActionCard(
                  label: 'New Expense',
                  icon: Icons.money_off_rounded,
                  gradient: const [Color(0xFFEF6820), Color(0xFFCF4E0E)],
                  onTap: () => _nav(context, const ExpenseFormView(), dashboard),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      );
    }

    final filteredRevenueTrend = _filterTrend(dashboard.revenueTrend, _selectedPeriodIndex);
    final filteredExpenseTrend = _filterTrend(dashboard.expenseTrend, _selectedPeriodIndex);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: RefreshIndicator(
        onRefresh: () async => dashboard.fetchDashboard(),
        child: ListView(
          padding: padding,
          children: [
            // Header with sliding animated period selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard', style: AppTextStyles.h1),
                      const SizedBox(height: 4),
                      Text('Your financial overview at a glance', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                if (!isMobile)
                  SizedBox(
                    width: 280,
                    child: _PeriodSelector(
                      selectedIndex: _selectedPeriodIndex,
                      periods: const ['30 Days', 'Quarter', 'Year'],
                      onChanged: (idx) => setState(() => _selectedPeriodIndex = idx),
                    ),
                  ),
              ],
            ),
            if (isMobile) ...[
              const SizedBox(height: 16),
              _PeriodSelector(
                selectedIndex: _selectedPeriodIndex,
                periods: const ['30 Days', 'Quarter', 'Year'],
                onChanged: (idx) => setState(() => _selectedPeriodIndex = idx),
              ),
            ],
            const SizedBox(height: 24),

            // Primary Metric Cards Grid
            GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isMobile ? 1.45 : 1.6,
              children: [
                _DashboardMetricCard(
                  title: 'Revenue',
                  value: '₹${_format(dashboard.revenue)}',
                  icon: Icons.trending_up_rounded,
                  iconGradient: const [Color(0xFF0E9384), Color(0xFF0A7569)],
                  trendValues: revSpark,
                  trendColor: const Color(0xFF0E9384),
                ),
                _DashboardMetricCard(
                  title: 'Expenses',
                  value: '₹${_format(dashboard.totalExpenses)}',
                  icon: Icons.trending_down_rounded,
                  iconGradient: const [Color(0xFFEF6820), Color(0xFFCF4E0E)],
                  trendValues: expSpark,
                  trendColor: const Color(0xFFEF6820),
                ),
                _DashboardMetricCard(
                  title: 'Net Profit',
                  value: '₹${_format(dashboard.netProfit)}',
                  icon: Icons.account_balance_wallet_rounded,
                  iconGradient: dashboard.netProfit >= 0
                      ? const [Color(0xFF6366F1), Color(0xFF4F46E5)]
                      : const [Color(0xFFD92D20), Color(0xFFB42318)],
                  trendValues: profitSpark,
                  trendColor: dashboard.netProfit >= 0 ? const Color(0xFF6366F1) : const Color(0xFFD92D20),
                ),
                _DashboardMetricCard(
                  title: 'Tax Liability',
                  value: '₹${_format(dashboard.totalTax)}',
                  icon: Icons.receipt_rounded,
                  iconGradient: const [Color(0xFF7B1FA2), Color(0xFF5E1781)],
                  trendValues: taxSpark,
                  trendColor: const Color(0xFF7B1FA2),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Receivables & Payables Row
            GridView.count(
              crossAxisCount: isMobile ? 1 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isMobile ? 3.2 : 4.5,
              children: [
                _DashboardMetricCard(
                  title: 'Receivables',
                  value: '₹${_format(dashboard.receivables)}',
                  subtitle: 'Pending collections from buyers',
                  icon: Icons.arrow_circle_left_rounded,
                  iconGradient: const [Color(0xFFDC6803), Color(0xFFB95002)],
                  trendValues: const [],
                  trendColor: const Color(0xFFDC6803),
                ),
                _DashboardMetricCard(
                  title: 'Payables',
                  value: '₹${_format(dashboard.payables)}',
                  subtitle: 'Pending payments to vendors',
                  icon: Icons.arrow_circle_right_rounded,
                  iconGradient: const [Color(0xFFB42318), Color(0xFF911810)],
                  trendValues: const [],
                  trendColor: const Color(0xFFB42318),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Interactive Charts Layout
            if (isMobile) ...[
              _InteractiveSplineAreaChart(
                revenueTrend: filteredRevenueTrend,
                expenseTrend: filteredExpenseTrend,
              ),
              const SizedBox(height: 16),
              _DonutBreakdownChart(
                revenue: dashboard.revenue,
                expenses: dashboard.totalExpenses + dashboard.purchases,
                netProfit: dashboard.netProfit,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _InteractiveSplineAreaChart(
                      revenueTrend: filteredRevenueTrend,
                      expenseTrend: filteredExpenseTrend,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _DonutBreakdownChart(
                      revenue: dashboard.revenue,
                      expenses: dashboard.totalExpenses + dashboard.purchases,
                      netProfit: dashboard.netProfit,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),

            // Secondary Content Layout (Recent Invoices & Quick Actions)
            if (isMobile) ...[
              _buildRecentInvoicesSection(context, dashboard),
              const SizedBox(height: 24),
              _buildQuickActionsSection(context, dashboard),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildRecentInvoicesSection(context, dashboard),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildQuickActionsSection(context, dashboard),
                  ),
                ],
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentInvoicesSection(BuildContext context, DashboardProvider dashboard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Invoices', style: AppTextStyles.h3),
        const SizedBox(height: 12),
        dashboard.recentInvoices.isEmpty
            ? Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(child: Text('No invoices yet', style: AppTextStyles.bodySmall)),
              )
            : Column(
                children: dashboard.recentInvoices
                    .map((inv) => _RecentInvoiceRow(
                          invoice: inv,
                          onTap: () {
                            // Can click row to view detail if needed
                          },
                        ))
                    .toList(),
              ),
      ],
    );
  }

  Widget _buildQuickActionsSection(BuildContext context, DashboardProvider dashboard) {
    final isMobile = AdaptiveLayout.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTextStyles.h3),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isMobile ? 1 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isMobile ? 3.8 : 2.5,
          children: [
            _QuickActionCard(
              label: 'New Invoice',
              icon: Icons.description_rounded,
              gradient: const [Color(0xFF0E9384), Color(0xFF0A7569)],
              onTap: () => _nav(context, const InvoiceFormView(), dashboard),
            ),
            _QuickActionCard(
              label: 'Add Party',
              icon: Icons.person_add_rounded,
              gradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
              onTap: () => _navDialog(context, const ContactFormView(), dashboard),
            ),
            _QuickActionCard(
              label: 'Record Payment',
              icon: Icons.payments_rounded,
              gradient: const [Color(0xFF067647), Color(0xFF045835)],
              onTap: () => _navPayment(context, dashboard),
            ),
            _QuickActionCard(
              label: 'New Expense',
              icon: Icons.money_off_rounded,
              gradient: const [Color(0xFFEF6820), Color(0xFFCF4E0E)],
              onTap: () => _nav(context, const ExpenseFormView(), dashboard),
            ),
          ],
        ),
      ],
    );
  }

  String _format(double value) {
    if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(1)}Cr';
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  void _nav(BuildContext context, Widget view, DashboardProvider dashboard) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => view)).then((_) => dashboard.fetchDashboard());
  }

  void _navDialog(BuildContext context, Widget view, DashboardProvider dashboard) {
    showDialog(context: context, builder: (_) => view).then((_) => dashboard.fetchDashboard());
  }

  void _navPayment(BuildContext context, DashboardProvider dashboard) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: PaymentFormView(
          mode: 'receipt',
          onSuccess: () {
            Navigator.of(ctx).pop();
            dashboard.fetchDashboard();
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Period Selector (animated capsule slider)
// ─────────────────────────────────────────────────────────────────────────────
class _PeriodSelector extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<String> periods;

  const _PeriodSelector({
    required this.selectedIndex,
    required this.onChanged,
    required this.periods,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / periods.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                left: selectedIndex * tabWidth,
                width: tabWidth,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: List.generate(periods.length, (i) {
                  final isSelected = selectedIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(i),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? AppColors.brandNavy : AppColors.textMuted,
                          ),
                          child: Text(periods[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sparkline Mini Chart (metric card velocity indicators)
// ─────────────────────────────────────────────────────────────────────────────
class _SparklineMiniChart extends StatelessWidget {
  final List<double> values;
  final Color color;

  const _SparklineMiniChart({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 55,
      height: 25,
      child: CustomPaint(
        painter: _SparklinePainter(values, color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;

    final dx = size.width / (values.length - 1);
    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - ((values[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Glowing Metric Card
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardMetricCard extends StatefulWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final List<Color> iconGradient;
  final List<double> trendValues;
  final Color trendColor;
  final VoidCallback? onTap;

  const _DashboardMetricCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.iconGradient,
    required this.trendValues,
    required this.trendColor,
    this.onTap,
  });

  @override
  State<_DashboardMetricCard> createState() => _DashboardMetricCardState();
}

class _DashboardMetricCardState extends State<_DashboardMetricCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.015),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.iconGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: widget.iconGradient.first.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, size: 16, color: Colors.white),
                  ),
                  const Spacer(),
                  if (widget.trendValues.isNotEmpty)
                    _SparklineMiniChart(values: widget.trendValues, color: widget.trendColor),
                ],
              ),
              const Spacer(),
              Text(
                widget.value,
                style: AppTextStyles.h1.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.title,
                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: AppTextStyles.caption.copyWith(fontSize: 9, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive Spline Area Chart
// ─────────────────────────────────────────────────────────────────────────────
class _InteractiveSplineAreaChart extends StatefulWidget {
  final List<dynamic> revenueTrend;
  final List<dynamic> expenseTrend;

  const _InteractiveSplineAreaChart({
    required this.revenueTrend,
    required this.expenseTrend,
  });

  @override
  State<_InteractiveSplineAreaChart> createState() => _InteractiveSplineAreaChartState();
}

class _InteractiveSplineAreaChartState extends State<_InteractiveSplineAreaChart> {
  int? _hoveredIndex;
  Offset? _hoverOffset;

  @override
  Widget build(BuildContext context) {
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final revenue = widget.revenueTrend.map((d) => double.tryParse((d['total'] ?? 0).toString()) ?? 0.0).toList();
    final expenses = widget.expenseTrend.map((d) => double.tryParse((d['total'] ?? 0).toString()) ?? 0.0).toList();

    if (revenue.isEmpty) revenue.addAll([0, 0]);
    if (expenses.isEmpty) expenses.addAll([0, 0]);

    final maxLength = revenue.length > expenses.length ? revenue.length : expenses.length;

    final List<String> labels = [];
    for (int i = 0; i < maxLength; i++) {
      int monthNum = 0;
      if (i < widget.revenueTrend.length) {
        monthNum = (double.tryParse((widget.revenueTrend[i]['month'] ?? 0).toString()) ?? 0).toInt();
      } else if (i < widget.expenseTrend.length) {
        monthNum = (double.tryParse((widget.expenseTrend[i]['month'] ?? 0).toString()) ?? 0).toInt();
      }
      labels.add(monthNum > 0 && monthNum <= 12 ? monthNames[monthNum - 1] : '?');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Financial Performance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Revenue and expenses over time', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                ],
              ),
              const Spacer(),
              const _LegendItem(color: Color(0xFF0E9384), label: 'Revenue'),
              const SizedBox(width: 12),
              const _LegendItem(color: Color(0xFFEF6820), label: 'Expenses'),
            ],
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onPanUpdate: (details) {
              _detectHover(details.localPosition, maxLength, context);
            },
            onPanDown: (details) {
              _detectHover(details.localPosition, maxLength, context);
            },
            onPanEnd: (_) {
              setState(() {
                _hoveredIndex = null;
                _hoverOffset = null;
              });
            },
            onTapUp: (_) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _hoveredIndex = null;
                    _hoverOffset = null;
                  });
                }
              });
            },
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: CustomPaint(
                painter: _SplineChartPainter(
                  revenue: revenue,
                  expenses: expenses,
                  labels: labels,
                  hoveredIndex: _hoveredIndex,
                  hoverOffset: _hoverOffset,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _detectHover(Offset localPos, int length, BuildContext context) {
    if (length == 0) return;
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width - 32;

    final chartStartX = 40.0;
    final chartEndX = width - 10.0;
    final chartWidth = chartEndX - chartStartX;

    final x = localPos.dx;
    if (x >= chartStartX && x <= chartEndX) {
      final percentage = (x - chartStartX) / chartWidth;
      final index = (percentage * (length - 1)).round().clamp(0, length - 1);
      setState(() {
        _hoveredIndex = index;
        _hoverOffset = localPos;
      });
    }
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _SplineChartPainter extends CustomPainter {
  final List<double> revenue;
  final List<double> expenses;
  final List<String> labels;
  final int? hoveredIndex;
  final Offset? hoverOffset;

  _SplineChartPainter({
    required this.revenue,
    required this.expenses,
    required this.labels,
    this.hoveredIndex,
    this.hoverOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double paddingLeft = 40.0;
    const double paddingRight = 10.0;
    const double paddingTop = 15.0;
    const double paddingBottom = 20.0;

    final chartWidth = size.width - paddingLeft - paddingRight;
    final chartHeight = size.height - paddingTop - paddingBottom;

    final allValues = [...revenue, ...expenses];
    final maxVal = allValues.isEmpty ? 1.0 : allValues.reduce((a, b) => a > b ? a : b);
    final limit = maxVal > 0 ? maxVal * 1.15 : 100.0;

    final gridCount = 4;
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= gridCount; i++) {
      final y = paddingTop + chartHeight - (i / gridCount) * chartHeight;
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      final gridVal = (i / gridCount) * limit;
      String labelStr = _formatYAxis(gridVal);

      textPainter.text = TextSpan(
        text: labelStr,
        style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontWeight: FontWeight.w500),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2));
    }

    final int length = labels.length;
    if (length == 0) return;

    final dx = length > 1 ? chartWidth / (length - 1) : chartWidth;
    final List<Offset> revPoints = [];
    final List<Offset> expPoints = [];

    for (int i = 0; i < length; i++) {
      final x = paddingLeft + i * dx;

      final revY = paddingTop + chartHeight - ((i < revenue.length ? revenue[i] : 0) / limit) * chartHeight;
      revPoints.add(Offset(x, revY));

      final expY = paddingTop + chartHeight - ((i < expenses.length ? expenses[i] : 0) / limit) * chartHeight;
      expPoints.add(Offset(x, expY));

      textPainter.text = TextSpan(
        text: labels[i],
        style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontWeight: FontWeight.w500),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - paddingBottom + 6));
    }

    _drawSplineCurve(canvas, revPoints, const Color(0xFF0E9384), chartHeight);
    _drawSplineCurve(canvas, expPoints, const Color(0xFFEF6820), chartHeight);

    if (hoveredIndex != null && hoveredIndex! < length) {
      final hoverX = revPoints[hoveredIndex!].dx;

      final dashedPaint = Paint()
        ..color = AppColors.brandNavy.withValues(alpha: 0.2)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      double curY = paddingTop;
      while (curY < size.height - paddingBottom) {
        canvas.drawLine(Offset(hoverX, curY), Offset(hoverX, curY + 4), dashedPaint);
        curY += 8;
      }

      final revPt = revPoints[hoveredIndex!];
      final expPt = expPoints[hoveredIndex!];

      _drawPulseDot(canvas, revPt, const Color(0xFF0E9384));
      _drawPulseDot(canvas, expPt, const Color(0xFFEF6820));

      _drawTooltipBox(canvas, size, revPt, expPt, hoveredIndex!);
    }
  }

  void _drawSplineCurve(Canvas canvas, List<Offset> points, Color color, double chartHeight) {
    if (points.length < 2) return;

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cp1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final cp2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }

    final double bottomY = 15.0 + chartHeight;
    final fillPath = Path.from(path);
    fillPath.lineTo(points.last.dx, bottomY);
    fillPath.lineTo(points.first.dx, bottomY);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 15),
        Offset(0, bottomY),
        [color.withValues(alpha: 0.12), color.withValues(alpha: 0.0)],
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);
  }

  void _drawPulseDot(Canvas canvas, Offset pt, Color color) {
    final outerRing = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final inner = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(pt, 7, outerRing);
    canvas.drawCircle(pt, 4, stroke);
    canvas.drawCircle(pt, 2.5, inner);
  }

  void _drawTooltipBox(Canvas canvas, Size size, Offset revPt, Offset expPt, int index) {
    final monthName = labels[index];
    final revVal = revenue[index];
    final expVal = expenses[index];

    final tooltipStr = '$monthName\nRev: ₹${_formatTooltip(revVal)}\nExp: ₹${_formatTooltip(expVal)}';
    final textSpan = TextSpan(
      text: tooltipStr,
      style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.4, fontWeight: FontWeight.w600),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();

    final boxW = tp.width + 16;
    final boxH = tp.height + 12;

    double boxX = revPt.dx - boxW / 2;
    boxX = boxX.clamp(40.0, size.width - boxW - 10.0);
    double boxY = (revPt.dy < expPt.dy ? revPt.dy : expPt.dy) - boxH - 12;
    if (boxY < 10) boxY = 10;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(boxX, boxY, boxW, boxH),
      const Radius.circular(8),
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(rect, bgPaint);
    canvas.drawRRect(rect, borderPaint);

    tp.paint(canvas, Offset(boxX + 8, boxY + 6));
  }

  String _formatYAxis(double val) {
    if (val >= 10000000) return '${(val / 10000000).toStringAsFixed(1)}Cr';
    if (val >= 100000) return '${(val / 100000).toStringAsFixed(0)}L';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  String _formatTooltip(double val) {
    if (val >= 100000) return '${(val / 100000).toStringAsFixed(1)}L';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _SplineChartPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Profitability Split Donut Chart
// ─────────────────────────────────────────────────────────────────────────────
class _DonutBreakdownChart extends StatelessWidget {
  final double revenue;
  final double expenses;
  final double netProfit;

  const _DonutBreakdownChart({
    required this.revenue,
    required this.expenses,
    required this.netProfit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profitability Split', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Distribution of income', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 120,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      revenue: revenue,
                      expenses: expenses,
                      netProfit: netProfit,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BreakdownLegend(
                      color: const Color(0xFFEF6820),
                      label: 'Expenses',
                      value: expenses,
                      percentage: revenue > 0 ? (expenses / revenue) * 100 : 0.0,
                    ),
                    const SizedBox(height: 12),
                    _BreakdownLegend(
                      color: const Color(0xFF6366F1),
                      label: 'Net Profit',
                      value: netProfit,
                      percentage: revenue > 0 ? (netProfit / revenue) * 100 : 0.0,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double revenue;
  final double expenses;
  final double netProfit;

  _DonutPainter({
    required this.revenue,
    required this.expenses,
    required this.netProfit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.height < size.width ? size.height : size.width) / 2;
    const strokeWidth = 12.0;
    final paintRadius = radius - strokeWidth / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final double total = revenue > 0 ? revenue : 1.0;
    final double expRatio = expenses.clamp(0, total) / total;
    final double profitRatio = netProfit.clamp(0, total) / total;

    paint.color = AppColors.borderLight;
    canvas.drawCircle(center, paintRadius, paint);

    const double pi = 3.1415926535;

    if (netProfit < 0) {
      paint.color = const Color(0xFFEF6820);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: paintRadius),
        -pi / 2,
        2 * pi,
        false,
        paint,
      );
    } else {
      final double expAngle = expRatio * 2 * pi;
      final double profitAngle = profitRatio * 2 * pi;

      double startAngle = -pi / 2;

      if (expAngle > 0) {
        paint.color = const Color(0xFFEF6820);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: paintRadius),
          startAngle,
          expAngle,
          false,
          paint,
        );
        startAngle += expAngle;
      }

      if (profitAngle > 0) {
        paint.color = const Color(0xFF6366F1);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: paintRadius),
          startAngle,
          profitAngle,
          false,
          paint,
        );
      }
    }

    final netProfitPercent = revenue > 0 ? (netProfit / revenue) * 100 : 0.0;
    final labelStr = netProfitPercent >= 0 ? '${netProfitPercent.toStringAsFixed(0)}%' : 'Loss';
    final textSpan = TextSpan(
      text: labelStr,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: netProfitPercent >= 0 ? const Color(0xFF6366F1) : const Color(0xFFEF6820),
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2 - 2));

    final subSpan = TextSpan(
      text: netProfitPercent >= 0 ? 'Margin' : 'Net Margin',
      style: const TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    );
    final tpsub = TextPainter(text: subSpan, textDirection: TextDirection.ltr);
    tpsub.layout();
    tpsub.paint(canvas, Offset(center.dx - tpsub.width / 2, center.dy + tp.height / 2 - 3));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _BreakdownLegend extends StatelessWidget {
  final Color color;
  final String label;
  final double value;
  final double percentage;

  const _BreakdownLegend({
    required this.color,
    required this.label,
    required this.value,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(
                '₹${_format(value)} (${percentage.toStringAsFixed(0)}%)',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _format(double val) {
    if (val >= 100000) return '${(val / 100000).toStringAsFixed(1)}L';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Invoice Row Widget
// ─────────────────────────────────────────────────────────────────────────────
class _RecentInvoiceRow extends StatefulWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onTap;

  const _RecentInvoiceRow({required this.invoice, required this.onTap});

  @override
  State<_RecentInvoiceRow> createState() => _RecentInvoiceRowState();
}

class _RecentInvoiceRowState extends State<_RecentInvoiceRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final String clientName = inv['contact']?['name'] ?? 'Guest Customer';
    final String initials = clientName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();
    final double total = double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;

    final List<Color> avatarGradient = _getAvatarGradient(initials);

    return FocusableActionDetector(
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: _isHovered ? AppColors.brandNavy.withValues(alpha: 0.15) : AppColors.border,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: avatarGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials.isNotEmpty ? initials : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv['invoice_number'] ?? 'INV', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(clientName, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  StatusBadge.fromInvoiceStatus(inv['status'] ?? 'DRAFT'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getAvatarGradient(String initials) {
    if (initials.isEmpty) return [const Color(0xFF64748B), const Color(0xFF475569)];
    final code = initials.codeUnitAt(0) % 5;
    switch (code) {
      case 0: return [const Color(0xFF6366F1), const Color(0xFF4F46E5)];
      case 1: return [const Color(0xFF0EA5E9), const Color(0xFF0284C7)];
      case 2: return [const Color(0xFF10B981), const Color(0xFF059669)];
      case 3: return [const Color(0xFFF59E0B), const Color(0xFFD97706)];
      default: return [const Color(0xFFEC4899), const Color(0xFFDB2777)];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Action Card Widget
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: _isHovered ? widget.gradient.first.withValues(alpha: 0.3) : AppColors.border,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: widget.gradient.first.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
