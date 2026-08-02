/// Cash Book report screen — mirrors the P&L date-range filter pattern.
///
/// Displays a chronological register of all cash account transactions with
/// opening balance, running balance, and summary totals.
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
import '../models/cash_book.dart';
import '../services/financial_statement_service.dart';

// ---------------------------------------------------------------------------
// Riverpod state — date-range filters drive the API call.
// ---------------------------------------------------------------------------

final cashBookDateFromProvider = StateProvider<String?>((ref) => null);
final cashBookDateToProvider = StateProvider<String?>((ref) => null);

final cashBookReportProvider = FutureProvider.autoDispose<CashBookReport>((
  ref,
) async {
  final dateFrom = ref.watch(cashBookDateFromProvider);
  final dateTo = ref.watch(cashBookDateToProvider);
  final res = await ref
      .watch(financialStatementServiceProvider)
      .getCashBook(startDate: dateFrom, endDate: dateTo);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CashBookScreen extends ConsumerStatefulWidget {
  const CashBookScreen({super.key});
  @override
  ConsumerState<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends ConsumerState<CashBookScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(cashBookReportProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Cash Book',
            subtitle: 'Cash transaction register for the period.',
            actions: [_buildDateFilter(colors)],
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => const ShimmerSkeleton(
                child: Padding(
                  padding: EdgeInsets.all(ApexSpacing.xl),
                  child: Column(
                    children: [
                      TableRowSkeleton(columns: 5),
                      TableRowSkeleton(columns: 5),
                      TableRowSkeleton(columns: 5),
                      TableRowSkeleton(columns: 5),
                    ],
                  ),
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(cashBookReportProvider),
              ),
              data: (report) {
                if (report.inflows.isEmpty && report.outflows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.account_balance_wallet_rounded,
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

  // -----------------------------------------------------------------------
  // Date filter
  // -----------------------------------------------------------------------

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
          child: Text(
            '–',
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ApexRadius_md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius_md),
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
        ref.read(cashBookDateFromProvider.notifier).state = _toApiDate(picked);
      } else {
        _toDate = picked;
        ref.read(cashBookDateToProvider.notifier).state = _toApiDate(picked);
      }
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
    CashBookReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final merged = _buildMergedRows(report);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        ApexSpacing.sm,
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        isMobile ? ApexSpacing.lg : ApexSpacing.xl,
      ),
      child: Column(
        children: [
          // Opening Balance card
          _openingBalanceCard(report, colors, fmt),
          const SizedBox(height: ApexSpacing.lg),
          // Register table
          _registerCard(merged, report, colors, fmt),
        ],
      ),
    );
  }

  Widget _openingBalanceCard(
    CashBookReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            color: colors.primary,
            size: 24,
          ),
          const SizedBox(width: ApexSpacing.md),
          Expanded(
            child: Text(
              'Opening Balance',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          MonetaryText(
            value: fmt.currency(report.openingBalance),
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _registerCard(
    List<_MergedRow> merged,
    CashBookReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return ApexCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMobile)
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: ApexSpacing.lg,
                vertical: ApexSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(flex: 18, child: Text('DATE', style: _th(colors))),
                  Expanded(
                    flex: 32,
                    child: Text('DESCRIPTION', style: _th(colors)),
                  ),
                  Expanded(
                    flex: 18,
                    child: Text(
                      'DEBIT',
                      textAlign: TextAlign.right,
                      style: _th(colors),
                    ),
                  ),
                  Expanded(
                    flex: 18,
                    child: Text(
                      'CREDIT',
                      textAlign: TextAlign.right,
                      style: _th(colors),
                    ),
                  ),
                  Expanded(
                    flex: 20,
                    child: Text(
                      'BALANCE',
                      textAlign: TextAlign.right,
                      style: _th(colors),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: ApexSpacing.md,
                vertical: ApexSpacing.md,
              ),
              child: Text(
                'Transactions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
          if (merged.isEmpty)
            const Padding(
              padding: EdgeInsets.all(ApexSpacing.lg),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No transactions',
              ),
            )
          else if (isMobile)
            ...merged.map((row) => _mobileRowWidget(row, colors, fmt))
          else
            ...merged.map((row) => _rowWidget(row, colors, fmt)),
          _buildFooter(report, colors, fmt),
        ],
      ),
    );
  }

  Widget _mobileRowWidget(
    _MergedRow row,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(ApexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.sm),
          Text(
            _shortDate(row.date),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          _mobileAmountRow(
            'Debit',
            row.debit > 0 ? fmt.currency(row.debit) : '—',
            colors,
          ),
          const SizedBox(height: ApexSpacing.xs),
          _mobileAmountRow(
            'Credit',
            row.credit > 0 ? fmt.currency(row.credit) : '—',
            colors,
          ),
          const Divider(height: ApexSpacing.lg),
          _mobileAmountRow(
            'Balance',
            fmt.currency(row.balance),
            colors,
            strong: true,
            danger: row.balance < 0,
          ),
        ],
      ),
    );
  }

  Widget _rowWidget(_MergedRow row, ApexColors colors, NumberFormatter fmt) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ApexSpacing.lg,
        vertical: ApexSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 18,
            child: Text(
              _shortDate(row.date),
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 32,
            child: Text(
              row.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: MonetaryText(
              value: row.debit > 0 ? fmt.currency(row.debit) : '—',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: row.debit > 0 ? colors.textPrimary : colors.textMuted,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 18,
            child: MonetaryText(
              value: row.credit > 0 ? fmt.currency(row.credit) : '—',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: row.credit > 0 ? colors.textPrimary : colors.textMuted,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 20,
            child: MonetaryText(
              value: fmt.currency(row.balance),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: row.balance >= 0 ? colors.textPrimary : colors.danger,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    CashBookReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    if (ResponsiveLayout.isMobile(context)) {
      return Container(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          border: Border(top: BorderSide(color: colors.border, width: 1.5)),
        ),
        padding: const EdgeInsets.all(ApexSpacing.md),
        child: Column(
          children: [
            _mobileAmountRow(
              'Cash inflow',
              fmt.currency(report.cashInflow),
              colors,
              strong: true,
            ),
            const SizedBox(height: ApexSpacing.xs),
            _mobileAmountRow(
              'Cash outflow',
              fmt.currency(report.cashOutflow),
              colors,
              strong: true,
              danger: true,
            ),
            const SizedBox(height: ApexSpacing.xs),
            _mobileAmountRow(
              'Closing balance',
              fmt.currency(report.closingBalance),
              colors,
              strong: true,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.border, width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ApexSpacing.lg,
        vertical: ApexSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 50,
            child: Text(
              'TOTAL',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: colors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: MonetaryText(
              value: fmt.currency(report.cashInflow),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.success,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 18,
            child: MonetaryText(
              value: fmt.currency(report.cashOutflow),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.danger,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 20,
            child: MonetaryText(
              value: fmt.currency(report.closingBalance),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileAmountRow(
    String label,
    String value,
    ApexColors colors, {
    bool strong = false,
    bool danger = false,
  }) {
    final muted = value == '—';
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
        MonetaryText(
          value: value,
          fontSize: 13,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
          color: muted
              ? colors.textMuted
              : danger
              ? colors.danger
              : colors.textPrimary,
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /// Builds a merged chronological list of inflows (debit) and outflows
  /// (credit) with running balance computed from opening balance.
  List<_MergedRow> _buildMergedRows(CashBookReport report) {
    final list = <_MergedRow>[];
    for (final i in report.inflows) {
      list.add(
        _MergedRow(
          date: i.date,
          description: i.transactionDetails,
          debit: i.amount,
        ),
      );
    }
    for (final o in report.outflows) {
      list.add(
        _MergedRow(
          date: o.date,
          description: o.transactionDetails,
          credit: o.amount,
        ),
      );
    }
    list.sort((a, b) => a.date.compareTo(b.date));

    double running = report.openingBalance;
    for (final row in list) {
      running = running + row.debit - row.credit;
      row.balance = running;
    }
    return list;
  }

  /// Converts YYYY-MM-DD to DD/MM for the date column.
  static String _shortDate(String isoDate) {
    if (isoDate.length >= 10) {
      final parts = isoDate.split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}';
    }
    return isoDate;
  }

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}

// ---------------------------------------------------------------------------
// Internal display model — mutable running balance.
// ---------------------------------------------------------------------------

class _MergedRow {
  _MergedRow({
    required this.date,
    required this.description,
    this.debit = 0,
    this.credit = 0,
  });

  final String date;
  final String description;
  final double debit;
  final double credit;
  double balance = 0;
}
