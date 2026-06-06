import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/dashboard_provider.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';
import 'package:flutter_client/views/contacts/contact_form_view.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/invoices/invoice_detail_view.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';

class SalesDashboardView extends StatefulWidget {
  const SalesDashboardView({super.key});

  @override
  State<SalesDashboardView> createState() => _SalesDashboardViewState();
}

class _SalesDashboardViewState extends State<SalesDashboardView> {
  int _selectedPeriod = 0; // 0=30d, 1=Quarter, 2=Year
  String? _lastFyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fy = context.read<FinancialYearProvider>();
      _lastFyId = fy.activeYear?.id;
      context.read<DashboardProvider>().fetchDashboard();
    });
  }

  void _onFYChanged() {
    if (mounted) {
      context.read<DashboardProvider>().fetchDashboard();
    }
  }

  String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  String _fmtFull(double v) {
    return AmountFormat.format(v);
  }

  void _nav(Widget view) {
    final p = context.read<DashboardProvider>();
    Navigator.push(context, MaterialPageRoute(builder: (_) => view)).then((_) => p.fetchDashboard());
  }

  void _navPayment() {
    final p = context.read<DashboardProvider>();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: PaymentFormView(
          mode: 'receipt',
          onSuccess: () {
            Navigator.of(ctx).pop();
            p.fetchDashboard();
          },
        ),
      ),
    );
  }

  void _navContact() {
    final p = context.read<DashboardProvider>();
    showDialog(context: context, builder: (_) => const ContactFormView()).then((_) => p.fetchDashboard());
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DashboardProvider>();
    final fy = context.watch<FinancialYearProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);
    final padH = isMobile ? 16.0 : 24.0;

    // Re-fetch dashboard when FY changes
    if (fy.activeYear?.id != _lastFyId) {
      _lastFyId = fy.activeYear?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) d.fetchDashboard();
      });
    }

    if (d.isLoading) {
      return const Scaffold(backgroundColor: AppColors.bgLight, body: DashboardSkeleton());
    }
    if (d.errorMessage != null) {
      return ErrorState(message: d.errorMessage!, onRetry: () => d.fetchDashboard());
    }

    final hasData = d.revenue > 0 || d.totalExpenses > 0 || d.recentInvoices.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: RefreshIndicator(
        onRefresh: () async { await d.fetchDashboard(); HapticHelper.medium(); },
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: 16),
          children: [
            // ── Header ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard', style: AppTextStyles.display.copyWith(fontSize: 28)),
                      const SizedBox(height: 2),
                      Text('Your financial overview', style: AppTextStyles.caption.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                if (!isMobile)
                  _PeriodChip(
                    selected: _selectedPeriod,
                    periods: const ['30 Days', 'Quarter', 'Year'],
                    onChanged: (i) => setState(() => _selectedPeriod = i),
                  ),
              ],
            ),
            if (isMobile) ...[
              const SizedBox(height: 12),
              _PeriodChip(
                selected: _selectedPeriod,
                periods: const ['30 Days', 'Quarter', 'Year'],
                onChanged: (i) => setState(() => _selectedPeriod = i),
              ),
            ],
            const SizedBox(height: 20),

            // ── Business Snapshot ──
            if (!hasData)
              EmptyState(
                icon: Icons.dashboard_rounded,
                title: 'Welcome to Apex Books',
                subtitle: 'Create your first invoice or add a party to get started',
              )
            else ...[
              _BusinessSnapshot(
                revenue: d.revenue,
                receivables: d.receivables,
                payables: d.payables,
                cashReceived: d.cashReceived,
                gstLiability: d.totalGstLiability,
                netProfit: d.netProfit,
                format: _fmt,
                formatFull: _fmtFull,
              ),
              const SizedBox(height: 20),

              // ── Quick Actions ──
              _QuickActions(
                onNewInvoice: () => _nav(const InvoiceFormView()),
                onNewBill: () => _nav(const BillFormView()),
                onPayment: _navPayment,
                onNewExpense: () => _nav(const ExpenseFormView()),
                onAddParty: _navContact,
              ),
              const SizedBox(height: 24),

              // ── Two Column Layout (desktop) / Stacked (mobile) ──
              if (isMobile) ...[
                _RecentActivity(invoices: d.recentInvoices, format: _fmtFull),
                const SizedBox(height: 20),
                _OutstandingCollections(debtors: d.topDebtors, format: _fmt),
                const SizedBox(height: 20),
                _CashBank(balances: d.cashBankBalances, format: _fmt),
                const SizedBox(height: 20),
                _SalesTrend(
                  revenueTrend: d.revenueTrend,
                  expenseTrend: d.expenseTrend,
                  period: _selectedPeriod,
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RecentActivity(invoices: d.recentInvoices, format: _fmtFull),
                          const SizedBox(height: 20),
                          _SalesTrend(
                            revenueTrend: d.revenueTrend,
                            expenseTrend: d.expenseTrend,
                            period: _selectedPeriod,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _OutstandingCollections(debtors: d.topDebtors, format: _fmt),
                          const SizedBox(height: 20),
                          _CashBank(balances: d.cashBankBalances, format: _fmt),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Period Selector ──
class _PeriodChip extends StatelessWidget {
  final int selected;
  final List<String> periods;
  final ValueChanged<int> onChanged;

  const _PeriodChip({required this.selected, required this.periods, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(periods.length, (i) {
          final isSel = selected == i;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSel ? AppColors.bgSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isSel
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                    : null,
              ),
              child: Text(
                periods[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                  color: isSel ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Business Snapshot ──
class _BusinessSnapshot extends StatelessWidget {
  final double revenue, receivables, payables, cashReceived, gstLiability, netProfit;
  final String Function(double) format;
  final String Function(double) formatFull;

  const _BusinessSnapshot({
    required this.revenue,
    required this.receivables,
    required this.payables,
    required this.cashReceived,
    required this.gstLiability,
    required this.netProfit,
    required this.format,
    required this.formatFull,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final metrics = [
      _Metric('Revenue', revenue, AppColors.brandNavy, Icons.trending_up_rounded),
      _Metric('Receivables', receivables, AppColors.warning, Icons.arrow_circle_left_rounded),
      _Metric('Payables', payables, AppColors.error, Icons.arrow_circle_right_rounded),
      _Metric('Cash Received', cashReceived, AppColors.success, Icons.payments_rounded),
      _Metric('GST Due', gstLiability, AppColors.info, Icons.receipt_rounded),
      _Metric('Net Profit', netProfit, netProfit >= 0 ? AppColors.success : AppColors.error, Icons.account_balance_wallet_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Business Snapshot', style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              // Top row: 3 or 6 metrics
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _MetricCell(metric: metrics[0], format: format, formatFull: formatFull)),
                    _vertDivider(),
                    Expanded(child: _MetricCell(metric: metrics[1], format: format, formatFull: formatFull)),
                    if (!isMobile) ...[
                      _vertDivider(),
                      Expanded(child: _MetricCell(metric: metrics[2], format: format, formatFull: formatFull)),
                    ],
                  ],
                ),
              ),
              Divider(color: AppColors.borderLight, height: 1),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isMobile) ...[
                      Expanded(child: _MetricCell(metric: metrics[2], format: format, formatFull: formatFull)),
                      _vertDivider(),
                    ],
                    Expanded(child: _MetricCell(metric: metrics[3], format: format, formatFull: formatFull)),
                    _vertDivider(),
                    Expanded(child: _MetricCell(metric: metrics[4], format: format, formatFull: formatFull)),
                    if (!isMobile) ...[
                      _vertDivider(),
                      Expanded(child: _MetricCell(metric: metrics[5], format: format, formatFull: formatFull)),
                    ],
                  ],
                ),
              ),
              if (isMobile) ...[
                Divider(color: AppColors.borderLight, height: 1),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _MetricCell(metric: metrics[5], format: format, formatFull: formatFull)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _vertDivider() => Container(width: 1, color: AppColors.borderLight);
}

class _Metric {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  _Metric(this.label, this.value, this.color, this.icon);
}

class _MetricCell extends StatelessWidget {
  final _Metric metric;
  final String Function(double) format;
  final String Function(double) formatFull;

  const _MetricCell({required this.metric, required this.format, required this.formatFull});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 14, color: metric.color),
              const SizedBox(width: 6),
              Text(
                metric.label.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Tooltip(
            message: formatFull(metric.value),
            child: Text(
              '₹${format(metric.value)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: metric.color,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Actions ──
class _QuickActions extends StatelessWidget {
  final VoidCallback onNewInvoice, onNewBill, onPayment, onNewExpense, onAddParty;

  const _QuickActions({
    required this.onNewInvoice,
    required this.onNewBill,
    required this.onPayment,
    required this.onNewExpense,
    required this.onAddParty,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final actions = [
      _Action('New Invoice', Icons.description_rounded, onNewInvoice, AppColors.brandNavy),
      _Action('New Purchase', Icons.receipt_rounded, onNewBill, AppColors.textSecondary),
      _Action('Receive Payment', Icons.payments_rounded, onPayment, AppColors.success),
      _Action('Add Expense', Icons.money_off_rounded, onNewExpense, AppColors.error),
      _Action('Add Party', Icons.person_add_rounded, onAddParty, AppColors.info),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actions.map((a) => _ActionButton(action: a)).toList(),
        ),
      ],
    );
  }
}

class _Action {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  _Action(this.label, this.icon, this.onTap, this.color);
}

class _ActionButton extends StatelessWidget {
  final _Action action;
  const _ActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: AppRadius.button,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.button,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 14, color: action.color),
              const SizedBox(width: 6),
              Text(
                action.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Recent Activity ──
class _RecentActivity extends StatelessWidget {
  final List<dynamic> invoices;
  final String Function(double) format;

  const _RecentActivity({required this.invoices, required this.format});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Activity', style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: invoices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('No recent activity', style: AppTextStyles.bodySmall),
                  ),
                )
              : Column(
                  children: [
                    ...invoices.map((inv) => _InvoiceRow(inv: inv, format: format)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _InvoiceRow extends StatefulWidget {
  final dynamic inv;
  final String Function(double) format;
  const _InvoiceRow({required this.inv, required this.format});

  @override
  State<_InvoiceRow> createState() => _InvoiceRowState();
}

class _InvoiceRowState extends State<_InvoiceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    final num = inv['invoice_number']?.toString() ?? 'INV';
    final name = inv['contact_name']?.toString() ?? 'Guest';
    final total = double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;
    final status = inv['status']?.toString() ?? 'DRAFT';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          final id = inv['id']?.toString() ?? inv['invoice_id']?.toString();
          if (id != null) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: id)));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgLight : Colors.transparent,
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#$num',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.format(total),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  StatusBadge.fromInvoiceStatus(status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Outstanding Collections ──
class _OutstandingCollections extends StatelessWidget {
  final List<dynamic> debtors;
  final String Function(double) format;

  const _OutstandingCollections({required this.debtors, required this.format});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Outstanding Collections', style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: debtors.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('No outstanding receivables', style: AppTextStyles.bodySmall),
                  ),
                )
              : Column(
                  children: debtors.map((d) {
                    final name = d is Map ? d['name']?.toString() ?? 'Customer' : 'Customer';
                    final amt = d is Map ? double.tryParse((d['outstanding'] ?? 0).toString()) ?? 0.0 : 0.0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '₹${format(amt)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warning,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

// ── Cash & Bank ──
class _CashBank extends StatelessWidget {
  final List<dynamic> balances;
  final String Function(double) format;

  const _CashBank({required this.balances, required this.format});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cash & Bank', style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: balances.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('No accounts configured', style: AppTextStyles.bodySmall),
                  ),
                )
              : Column(
                  children: balances.map((a) {
                    final name = a is Map ? a['name']?.toString() ?? 'Account' : 'Account';
                    final bal = a is Map ? double.tryParse((a['current_balance'] ?? 0).toString()) ?? 0.0 : 0.0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '₹${format(bal)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

// ── Simple Bar Chart ──
class _SalesTrend extends StatelessWidget {
  final List<dynamic> revenueTrend;
  final List<dynamic> expenseTrend;
  final int period;

  const _SalesTrend({
    required this.revenueTrend,
    required this.expenseTrend,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    var rev = _filter(revenueTrend);
    var exp = _filter(expenseTrend);

    if (rev.isEmpty && exp.isEmpty) {
      return const SizedBox.shrink();
    }

    // Ensure same length
    final len = rev.length > exp.length ? rev.length : exp.length;
    while (rev.length < len) rev.add(0);
    while (exp.length < len) exp.add(0);

    final maxVal = [...rev, ...exp].reduce((a, b) => a > b ? a : b);
    final max = maxVal > 0 ? maxVal : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sales Trend', style: AppTextStyles.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Legend
              Row(
                children: [
                  _legendDot(AppColors.brandNavy),
                  const SizedBox(width: 4),
                  Text('Revenue', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  _legendDot(AppColors.error),
                  const SizedBox(width: 4),
                  Text('Expenses', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              // Bars
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(len, (i) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Revenue bar
                            Container(
                              width: double.infinity,
                              height: (rev[i] / max) * 80,
                              decoration: BoxDecoration(
                                color: AppColors.brandNavy,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Expense bar
                            Container(
                              width: double.infinity,
                              height: (exp[i] / max) * 40,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.5),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<double> _filter(List<dynamic> trend) {
    final vals = trend.map((d) => double.tryParse('${d is Map ? d['total'] ?? 0 : 0}') ?? 0.0).toList();
    if (vals.isEmpty) return [];
    if (period == 0) return vals.length > 6 ? vals.sublist(vals.length - 6) : vals;
    if (period == 1) return vals.length > 3 ? vals.sublist(vals.length - 3) : vals;
    return vals;
  }

  Widget _legendDot(Color c) => Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}
