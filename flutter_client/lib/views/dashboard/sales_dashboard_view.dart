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
import 'package:flutter_client/views/reports/party_statement_view.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/views/dashboard/mobile_home_view.dart';
import 'package:flutter_client/views/shared/design_system.dart';

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
      _fetchWithPeriod(_selectedPeriod);
    });
  }

  void _onFYChanged() {
    if (mounted) {
      _fetchWithPeriod(_selectedPeriod);
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => view)).then((_) => _fetchWithPeriod(_selectedPeriod));
  }

  void _fetchWithPeriod(int period) {
    final now = DateTime.now();
    String dateFrom;
    String dateTo = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    switch (period) {
      case 0: // 30 days
        final d = now.subtract(const Duration(days: 30));
        dateFrom = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        break;
      case 1: // Quarter
        final quarterStart = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
        dateFrom = '${quarterStart.year}-${quarterStart.month.toString().padLeft(2, '0')}-${quarterStart.day.toString().padLeft(2, '0')}';
        break;
      case 2: // Year (FY)
        final fy = context.read<FinancialYearProvider>();
        if (fy.activeYear != null) {
          final s = fy.activeYear!.startDate;
          final e = fy.activeYear!.endDate;
          dateFrom = '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
          dateTo = '${e.year}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}';
        } else {
          final fyStart = now.month >= 4 ? DateTime(now.year, 4, 1) : DateTime(now.year - 1, 4, 1);
          dateFrom = '${fyStart.year}-${fyStart.month.toString().padLeft(2, '0')}-${fyStart.day.toString().padLeft(2, '0')}';
        }
        break;
      default:
        dateFrom = '${now.year}-01-01';
    }
    
    context.read<DashboardProvider>().fetchDashboard(dateFrom: dateFrom, dateTo: dateTo);
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
      return Scaffold(backgroundColor: AppColors.bgLight, body: DashboardSkeleton());
    }
    if (d.errorMessage != null) {
      return ErrorState(message: d.errorMessage!, onRetry: () => d.fetchDashboard());
    }

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        body: MobileHomeView(),
      );
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
                    onChanged: (i) {
                      setState(() => _selectedPeriod = i);
                      _fetchWithPeriod(i);
                    },
                  ),
              ],
            ),
            if (isMobile) ...[
              const SizedBox(height: 12),
              _PeriodChip(
                selected: _selectedPeriod,
                periods: const ['30 Days', 'Quarter', 'Year'],
                onChanged: (i) {
                  setState(() => _selectedPeriod = i);
                  _fetchWithPeriod(i);
                },
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
              _KpiStrip(
                revenue: d.revenue,
                receivables: d.receivables,
                payables: d.payables,
                cashReceived: d.cashReceived,
                gstLiability: d.totalGstLiability,
                netProfit: d.netProfit,
                revenueTrend: d.revenueTrend,
                expenseTrend: d.expenseTrend,
                format: _fmt,
                formatFull: _fmtFull,
                gstEnabled: context.watch<SettingsProvider>().gstEnabled,
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

              // ── Overdue Alerts ──
              if (d.overdueAlerts.isNotEmpty) ...[
                _OverdueAlerts(alerts: d.overdueAlerts, format: _fmtFull),
                const SizedBox(height: 24),
              ],

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

// ── KPI Strip ──
/// Premium scrollable strip of financial KPI tiles.
class _KpiStrip extends StatelessWidget {
  final double revenue, receivables, payables, cashReceived, gstLiability, netProfit;
  final List<dynamic> revenueTrend;
  final List<dynamic> expenseTrend;
  final String Function(double) format;
  final String Function(double) formatFull;
  final bool gstEnabled;

  const _KpiStrip({
    required this.revenue,
    required this.receivables,
    required this.payables,
    required this.cashReceived,
    required this.gstLiability,
    required this.netProfit,
    required this.revenueTrend,
    required this.expenseTrend,
    required this.format,
    required this.formatFull,
    this.gstEnabled = true,
  });

  /// Returns +1 (up), -1 (down), or 0 (flat) by comparing the last two trend points.
  int _trend(List<dynamic> trend) {
    if (trend.length < 2) return 0;
    final last = double.tryParse(trend.last['value']?.toString() ?? '0') ?? 0;
    final prev = double.tryParse(trend[trend.length - 2]['value']?.toString() ?? '0') ?? 0;
    if (last > prev) return 1;
    if (last < prev) return -1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final revTrend = _trend(revenueTrend);

    final tiles = [
      AppKpiTile(
        label: 'Revenue',
        amountShort: '\u20b9${format(revenue)}',
        amountFull: formatFull(revenue),
        accentColor: AppColors.brandIndigo,
        icon: Icons.trending_up_rounded,
        trendDirection: revTrend,
      ),
      AppKpiTile(
        label: 'Receivables',
        amountShort: '\u20b9${format(receivables)}',
        amountFull: formatFull(receivables),
        accentColor: AppColors.amountReceivable,
        icon: Icons.arrow_circle_left_rounded,
        colorizeAmount: receivables > 0,
      ),
      AppKpiTile(
        label: 'Payables',
        amountShort: '\u20b9${format(payables)}',
        amountFull: formatFull(payables),
        accentColor: AppColors.amountPayable,
        icon: Icons.arrow_circle_right_rounded,
        colorizeAmount: payables > 0,
      ),
      AppKpiTile(
        label: 'Cash Received',
        amountShort: '\u20b9${format(cashReceived)}',
        amountFull: formatFull(cashReceived),
        accentColor: AppColors.success,
        icon: Icons.payments_rounded,
        trendDirection: revTrend,
      ),
      if (gstEnabled)
        AppKpiTile(
          label: 'GST Due',
          amountShort: '\u20b9${format(gstLiability)}',
          amountFull: formatFull(gstLiability),
          accentColor: AppColors.info,
          icon: Icons.receipt_rounded,
          colorizeAmount: gstLiability > 0,
        ),
      AppKpiTile(
        label: 'Net Profit',
        amountShort: '\u20b9${format(netProfit.abs())}',
        amountFull: (netProfit < 0 ? '-' : '') + formatFull(netProfit.abs()),
        accentColor: netProfit >= 0 ? AppColors.amountPositive : AppColors.amountNegative,
        icon: Icons.account_balance_wallet_rounded,
        colorizeAmount: true,
        trendDirection: netProfit >= 0 ? (revTrend != -1 ? 1 : -1) : -1,
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: 160, child: tiles[i]),
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
      _Action('New Invoice', Icons.description_rounded, onNewInvoice, AppColors.brandIndigo),
      _Action('New Purchase', Icons.receipt_rounded, onNewBill, AppColors.warning),
      _Action('Receive Payment', Icons.payments_rounded, onPayment, AppColors.success),
      _Action('Add Expense', Icons.money_off_rounded, onNewExpense, AppColors.error),
      _Action('Add Party', Icons.person_add_rounded, onAddParty, AppColors.info),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Quick Actions', style: AppTextStyles.h3),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 10),
        if (isMobile)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions.map((a) => AppQuickActionCard(
              label: a.label,
              icon: a.icon,
              color: a.color,
              onTap: a.onTap,
            )).toList(),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: actions.map((a) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: AppQuickActionCard(
                  label: a.label,
                  icon: a.icon,
                  color: a.color,
                  onTap: a.onTap,
                ),
              )).toList(),
            ),
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
        Row(
          children: [
            Text('Recent Activity', style: AppTextStyles.h3),
            const Spacer(),
            TextButton(
              onPressed: null, // navigates to invoice list
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandIndigo,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('View All'),
            ),
          ],
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    final contactId = d is Map ? d['contact_id']?.toString() : null;
                    return InkWell(
                      onTap: contactId != null
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PartyStatementView(
                                    initialContact: ContactModel(
                                      id: contactId,
                                      name: name,
                                      contactType: 'CUSTOMER',
                                      registrationType: 'CONSUMER',
                                      billingAddress: {},
                                      stateCode: '27',
                                      isActive: true,
                                    ),
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: Container(
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
                            if (contactId != null) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                            ],
                          ],
                        ),
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
                              height: (exp[i] / max) * 80,
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

// ── Overdue Alerts ──
class _OverdueAlerts extends StatelessWidget {
  final List<dynamic> alerts;
  final String Function(double) format;

  const _OverdueAlerts({required this.alerts, required this.format});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.error),
            const SizedBox(width: 6),
            Text('Overdue Alerts', style: AppTextStyles.h2.copyWith(fontSize: 20)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text('${alerts.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...alerts.map((a) {
          final severity = a['severity']?.toString() ?? 'medium';
          final daysOverdue = a['days_overdue'] ?? 0;
          final amount = double.tryParse((a['outstanding_amount'] ?? 0).toString()) ?? 0.0;
          final contactName = a['contact_name'] ?? 'Unknown';
          final invoiceNumber = a['invoice_number'] ?? '';
          final Color color;
          final IconData icon;
          if (severity == 'critical') {
            color = AppColors.error;
            icon = Icons.error_outline;
          } else if (severity == 'high') {
            color = const Color(0xFFF59E0B);
            icon = Icons.warning_amber_outlined;
          } else {
            color = AppColors.textMuted;
            icon = Icons.info_outline;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contactName, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                      Text('$invoiceNumber · $daysOverdue days overdue', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Text(format(amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          );
        }),
      ],
    );
  }
}
