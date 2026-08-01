/// Profit & Loss report screen — mirrors the TrialBalanceScreen pattern.
///
/// Displays revenue and expense sections with account-level detail and a
/// net profit/loss summary card at the bottom. Supports optional date-range
/// filtering via the PageHeader actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/profit_loss.dart';
import '../services/financial_statement_service.dart';

final pnlDateFromProvider = StateProvider<String?>((ref) => null);
final pnlDateToProvider = StateProvider<String?>((ref) => null);

final profitLossReportProvider = FutureProvider.autoDispose<ProfitLossReport>((
  ref,
) async {
  final dateFrom = ref.watch(pnlDateFromProvider);
  final dateTo = ref.watch(pnlDateToProvider);
  final res = await ref
      .watch(financialStatementServiceProvider)
      .getProfitLoss(dateFrom: dateFrom, dateTo: dateTo);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

class ProfitLossScreen extends ConsumerStatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  ConsumerState<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends ConsumerState<ProfitLossScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(pnlDateFromProvider.notifier).state = _toApiDate(_fromDate!);
        ref.read(pnlDateToProvider.notifier).state = _toApiDate(_toDate!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(profitLossReportProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Profit & Loss',
            subtitle: 'Income and expense summary for the period.',
            actions: [_buildDateFilter(colors)],
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => const ShimmerSkeleton(
                child: Padding(
                  padding: EdgeInsets.all(ApexSpacing.xl),
                  child: Column(
                    children: [
                      TableRowSkeleton(columns: 2),
                      TableRowSkeleton(columns: 2),
                      TableRowSkeleton(columns: 2),
                      TableRowSkeleton(columns: 2),
                      TableRowSkeleton(columns: 2),
                    ],
                  ),
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(profitLossReportProvider),
              ),
              data: (report) {
                if (report.revenueLines.isEmpty &&
                    report.expenseLines.isEmpty) {
                  return const EmptyState(
                    icon: Icons.bar_chart_rounded,
                    title: 'No data for this period',
                    subtitle: 'Try adjusting the date range.',
                  );
                }
                return _buildReport(report, colors, fmt);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilter(ApexColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dateChip(
          date: _fromDate,
          onTap: () => _pickDate(isFrom: true),
          colors: colors,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('–', style: TextStyle(color: colors.textMuted)),
        ),
        _dateChip(
          date: _toDate,
          onTap: () => _pickDate(isFrom: false),
          colors: colors,
        ),
      ],
    );
  }

  Widget _dateChip({
    required DateTime? date,
    required VoidCallback onTap,
    required ApexColors colors,
  }) {
    final label = date != null ? _fmtDate(date) : 'Select';
    return Semantics(
      button: true,
      label: 'Select date $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ApexRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(ApexRadius.md),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range_rounded,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: isFrom ? 'Select from date' : 'Select to date',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        ref.read(pnlDateFromProvider.notifier).state = _toApiDate(picked);
      } else {
        _toDate = picked;
        ref.read(pnlDateToProvider.notifier).state = _toApiDate(picked);
      }
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _toApiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildReport(
    ProfitLossReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        ApexSpacing.sm,
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        isMobile ? ApexSpacing.lg : ApexSpacing.xl,
      ),
      child: Column(
        children: [
          _buildSection(
            title: 'Income',
            items: report.revenueLines,
            total: report.totalRevenue,
            colors: colors,
            fmt: fmt,
          ),
          const SizedBox(height: ApexSpacing.lg),
          _buildSection(
            title: 'Expenses',
            items: report.expenseLines,
            total: report.totalExpenses,
            colors: colors,
            fmt: fmt,
          ),
          const SizedBox(height: ApexSpacing.lg),
          _buildNetProfit(report, colors, fmt),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<ProfitLossItem> items,
    required double total,
    required ApexColors colors,
    required NumberFormatter fmt,
  }) {
    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
              child: Text(
                'No $title entries for this period.',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(child: Text('ACCOUNT', style: _th(colors))),
                SizedBox(
                  width: 120,
                  child: Text(
                    'AMOUNT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ApexSpacing.xs),
            Divider(height: 1, color: colors.border),
            for (final item in items)
              Container(
                padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.accountName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (item.accountCode.isNotEmpty) ...[
                            const SizedBox(height: ApexSpacing.xs),
                            Text(
                              item.accountCode,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: MonetaryText(
                        value: fmt.currency(item.amount),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            Divider(height: 1, color: colors.border),
            Container(
              padding: const EdgeInsets.symmetric(vertical: ApexSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total $title',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: MonetaryText(
                      value: fmt.currency(total),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNetProfit(
    ProfitLossReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isProfitable = report.isProfitable;
    final label = isProfitable ? 'Net Profit' : 'Net Loss';
    final color = isProfitable ? colors.success : colors.danger;
    final icon = isProfitable
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;
    final isMobile = ResponsiveLayout.isMobile(context);

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Revenue: ${fmt.currency(report.totalRevenue)} — '
          'Expenses: ${fmt.currency(report.totalExpenses)}',
          style: TextStyle(fontSize: 12, color: colors.textMuted),
        ),
      ],
    );

    final amount = MonetaryText(
      value: fmt.currency(report.netProfit),
      fontSize: isMobile ? 18 : 20,
      fontWeight: FontWeight.w800,
      color: color,
      textAlign: isMobile ? TextAlign.left : TextAlign.right,
    );

    return ApexCard(
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: ApexSpacing.sm),
                summary,
                const SizedBox(height: ApexSpacing.md),
                amount,
              ],
            )
          : Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: ApexSpacing.md),
                Expanded(child: summary),
                amount,
              ],
            ),
    );
  }

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
