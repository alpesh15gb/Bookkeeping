/// Balance Sheet report screen — mirrors the TrialBalanceScreen pattern.
///
/// Displays Assets, Liabilities, and Equity sections with account-level
/// detail and section totals. Shows a balanced/unbalanced banner and a
/// final verification row. Supports as-on-date filtering via PageHeader
/// actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/balance_sheet.dart';
import '../services/financial_statement_service.dart';

// ---------------------------------------------------------------------------
// Riverpod state — as-on-date drives the API call.
// ---------------------------------------------------------------------------

final bsAsOnDateProvider = StateProvider<String?>((ref) => null);

final balanceSheetReportProvider =
    FutureProvider.autoDispose<BalanceSheetReport>((ref) async {
      final asOnDate = ref.watch(bsAsOnDateProvider);
      final res = await ref
          .watch(financialStatementServiceProvider)
          .getBalanceSheet(asOnDate: asOnDate);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BalanceSheetScreen extends ConsumerStatefulWidget {
  const BalanceSheetScreen({super.key});
  @override
  ConsumerState<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen> {
  DateTime? _asOnDate;

  @override
  void initState() {
    super.initState();
    _asOnDate = DateTime.now();
    // Push initial date to provider so the first API call respects it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bsAsOnDateProvider.notifier).state = _asOnDate!
            .toIso8601String()
            .split('T')[0];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(balanceSheetReportProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Balance Sheet',
            subtitle: 'Financial position as on the selected date.',
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
                onRetry: () => ref.invalidate(balanceSheetReportProvider),
              ),
              data: (report) {
                if (report.assets.isEmpty &&
                    report.liabilities.isEmpty &&
                    report.equity.isEmpty) {
                  return const EmptyState(
                    icon: Icons.account_balance_rounded,
                    title: 'No data available',
                    subtitle:
                        'There are no accounts with balances for this date.',
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

  // -----------------------------------------------------------------------
  // Date filter
  // -----------------------------------------------------------------------

  Widget _buildDateFilter(ApexColors colors) {
    return _dateChip(date: _asOnDate, onTap: () => _pickDate(), colors: colors);
  }

  Widget _dateChip({
    required DateTime? date,
    required VoidCallback onTap,
    required ApexColors colors,
  }) {
    final label = date != null ? _fmtDate(date) : 'Select date';
    return InkWell(
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
            const SizedBox(width: 6),
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
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOnDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select as-on date',
    );
    if (picked == null) return;
    setState(() {
      _asOnDate = picked;
      ref.read(bsAsOnDateProvider.notifier).state = _toApiDate(picked);
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _toApiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // -----------------------------------------------------------------------
  // Report body
  // -----------------------------------------------------------------------

  Widget _buildReport(
    BalanceSheetReport report,
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
          // Balanced / unbalanced banner
          _balanceBanner(report, colors),
          const SizedBox(height: ApexSpacing.lg),

          // Assets
          _buildSection(
            title: 'Assets',
            items: report.assets,
            total: report.totalAssets,
            colors: colors,
            fmt: fmt,
          ),
          const SizedBox(height: ApexSpacing.lg),

          // Liabilities
          _buildSection(
            title: 'Liabilities',
            items: report.liabilities,
            total: report.totalLiabilities,
            colors: colors,
            fmt: fmt,
          ),
          const SizedBox(height: ApexSpacing.lg),

          // Equity
          _buildEquitySection(report, colors, fmt),
          const SizedBox(height: ApexSpacing.lg),

          // Verification
          _buildVerification(report, colors, fmt),
        ],
      ),
    );
  }

  Widget _balanceBanner(BalanceSheetReport report, ApexColors colors) {
    final ok = report.isBalanced;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ApexSpacing.lg,
        vertical: ApexSpacing.md,
      ),
      decoration: BoxDecoration(
        color: (ok ? colors.success : colors.danger).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ApexRadius.md),
        border: Border.all(
          color: (ok ? colors.success : colors.danger).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: ok ? colors.success : colors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok ? 'Balance Sheet is balanced' : 'Balance Sheet out of balance',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ok ? colors.success : colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<BalanceSheetItem> items,
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
                'No $title entries.',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else ...[
            // Column headers
            Row(
              children: [
                Expanded(child: Text('ACCOUNT', style: _th(colors))),
                SizedBox(
                  width: 120,
                  child: Text(
                    'BALANCE',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ApexSpacing.xs),
            Divider(height: 1, color: colors.border),
            // Account rows
            for (final item in items)
              Container(
                padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.accountName,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: MonetaryText(
                        value: fmt.currency(item.balance),
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
            // Total row
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

  Widget _buildEquitySection(
    BalanceSheetReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    // totalEquity from the backend already includes netProfit for the period.
    // Do NOT add netProfit again — that would double-count.
    final equityTotal = report.totalEquity;

    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Equity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          if (report.equity.isEmpty && report.netProfit == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
              child: Text(
                'No equity entries.',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            )
          else ...[
            // Column headers
            Row(
              children: [
                Expanded(child: Text('ACCOUNT', style: _th(colors))),
                SizedBox(
                  width: 120,
                  child: Text(
                    'BALANCE',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ApexSpacing.xs),
            Divider(height: 1, color: colors.border),
            // Equity account rows
            for (final item in report.equity)
              Container(
                padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.accountName,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: MonetaryText(
                        value: fmt.currency(item.balance),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            // Current-period Net Profit line (standout)
            if (report.equity.isNotEmpty)
              Divider(height: 1, color: colors.border),
            Container(
              padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
              decoration: BoxDecoration(
                color: (report.netProfit >= 0 ? colors.success : colors.danger)
                    .withValues(alpha: 0.04),
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      report.netProfit >= 0
                          ? 'Net Profit (current period)'
                          : 'Net Loss (current period)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: report.netProfit >= 0
                            ? colors.success
                            : colors.danger,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: MonetaryText(
                      value: fmt.currency(
                        report.netProfit,
                      ), // Negative shown in ( ) per accounting standard
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: report.netProfit >= 0
                          ? colors.success
                          : colors.danger,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            // Total equity row
            Divider(height: 1, color: colors.border),
            Container(
              padding: const EdgeInsets.symmetric(vertical: ApexSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total Equity',
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
                      value: fmt.currency(equityTotal),
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

  Widget _buildVerification(
    BalanceSheetReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final ok = report.isBalanced;
    final liabEq = report.totalLiabilitiesEquity;

    return ApexCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Assets',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              MonetaryText(
                value: fmt.currency(report.totalAssets),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                textAlign: TextAlign.right,
              ),
            ],
          ),
          const SizedBox(height: ApexSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Liabilities + Equity',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              MonetaryText(
                value: fmt.currency(liabEq),
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                textAlign: TextAlign.right,
              ),
            ],
          ),
          const SizedBox(height: ApexSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                size: 18,
                color: ok ? colors.success : colors.danger,
              ),
              const SizedBox(width: 6),
              Text(
                ok ? 'Balanced' : 'Out of balance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ok ? colors.success : colors.danger,
                ),
              ),
            ],
          ),
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
