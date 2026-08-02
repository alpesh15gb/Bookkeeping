/// General Ledger screen — lists all accounts with opening/debit/credit/closing
/// balances for a given period. Tapping an account drills into its Account Ledger.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/search_bar.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../../trial_balance/models/trial_balance.dart';
import '../../trial_balance/services/trial_balance_service.dart';
import 'account_ledger_screen.dart';

// ---------------------------------------------------------------------------
// Riverpod state — as-of date drives the API call.
// ---------------------------------------------------------------------------

final generalLedgerDateToProvider = StateProvider<String?>((ref) => null);

final generalLedgerReportProvider =
    FutureProvider.autoDispose<TrialBalanceReport>((ref) async {
      final dateTo = ref.watch(generalLedgerDateToProvider);
      final res = await ref
          .watch(trialBalanceServiceProvider)
          .getTrialBalance(asOfDate: dateTo);
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GeneralLedgerScreen extends ConsumerStatefulWidget {
  const GeneralLedgerScreen({super.key});

  @override
  ConsumerState<GeneralLedgerScreen> createState() =>
      _GeneralLedgerScreenState();
}

class _GeneralLedgerScreenState extends ConsumerState<GeneralLedgerScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTime? _asOfDate;

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(generalLedgerDateToProvider.notifier).state = _toApiDate(
        _asOfDate!,
      );
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(generalLedgerReportProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'General Ledger',
            subtitle: _asOfDate != null
                ? 'Account balances as of ${_fmtDate(_asOfDate!)}.'
                : 'Account balances and summaries.',
            actions: [_buildDateFilter(colors)],
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 5),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(generalLedgerReportProvider),
              ),
              data: (report) {
                final q = _search.trim().toLowerCase();
                final lines = q.isEmpty
                    ? report.lines
                    : report.lines
                          .where(
                            (line) =>
                                line.accountName.toLowerCase().contains(q) ||
                                line.accountCode.toLowerCase().contains(q),
                          )
                          .toList();
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? ApexSpacing.md : ApexSpacing.xl,
                        0,
                        isMobile ? ApexSpacing.md : ApexSpacing.xl,
                        ApexSpacing.sm,
                      ),
                      child: ApexSearchBar(
                        controller: _searchCtrl,
                        hintText: 'Search account name or code…',
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Expanded(child: _reportTable(lines, report, colors, fmt)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Date filter
  // -------------------------------------------------------------------------

  Widget _buildDateFilter(ApexColors colors) {
    return Semantics(
      button: true,
      label: 'Select General Ledger as-of date',
      child: InkWell(
        onTap: _pickDate,
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
                _asOfDate != null ? _fmtDate(_asOfDate!) : 'Select date',
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOfDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select as-of date',
    );
    if (picked == null) return;
    setState(() => _asOfDate = picked);
    ref.read(generalLedgerDateToProvider.notifier).state = _toApiDate(picked);
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _toApiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // -------------------------------------------------------------------------
  // Report table
  // -------------------------------------------------------------------------

  Widget _reportTable(
    List<TrialBalanceLine> lines,
    TrialBalanceReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    if (ResponsiveLayout.isMobile(context)) {
      return _mobileReportList(lines, report, colors, fmt);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        ApexSpacing.xl,
        0,
        ApexSpacing.xl,
        ApexSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius_lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.lg,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(flex: 36, child: Text('ACCOUNT', style: _th(colors))),
                Expanded(
                  flex: 16,
                  child: Text(
                    'OPENING',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    'DEBIT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    'CREDIT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    'CLOSING',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching accounts',
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final line = lines[i];
                      return InkWell(
                        onTap: () => _openAccountLedger(line),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: colors.border),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: ApexSpacing.lg,
                            vertical: ApexSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 36,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        line.accountCode,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textMuted,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        line.accountName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 16,
                                child: MonetaryText(
                                  value: fmt.currency(line.openingBalance),
                                  fontSize: 13,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Expanded(
                                flex: 16,
                                child: line.totalDebits > 0
                                    ? MonetaryText(
                                        value: fmt.currency(line.totalDebits),
                                        fontSize: 13,
                                        textAlign: TextAlign.right,
                                      )
                                    : _dash(colors),
                              ),
                              Expanded(
                                flex: 16,
                                child: line.totalCredits > 0
                                    ? MonetaryText(
                                        value: fmt.currency(line.totalCredits),
                                        fontSize: 13,
                                        textAlign: TextAlign.right,
                                      )
                                    : _dash(colors),
                              ),
                              Expanded(
                                flex: 16,
                                child: MonetaryText(
                                  value: fmt.currency(line.closingBalance),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _desktopTotalsFooter(report, colors, fmt),
        ],
      ),
    );
  }

  Widget _mobileReportList(
    List<TrialBalanceLine> lines,
    TrialBalanceReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    if (lines.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching accounts',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        ApexSpacing.md,
        0,
        ApexSpacing.md,
        ApexSpacing.lg,
      ),
      itemCount: lines.length + 1,
      itemBuilder: (context, index) {
        if (index == lines.length) {
          return _mobileTotalsCard(report, colors, fmt);
        }
        return _mobileAccountCard(lines[index], colors, fmt);
      },
    );
  }

  Widget _mobileAccountCard(
    TrialBalanceLine line,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ApexSpacing.md),
      child: ApexCard(
        onTap: () => _openAccountLedger(line),
        padding: const EdgeInsets.all(ApexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.accountName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            if (line.accountCode.isNotEmpty) ...[
              const SizedBox(height: ApexSpacing.xs),
              Text(
                line.accountCode,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(height: ApexSpacing.md),
            _mobileAmountRow(
              'Opening',
              fmt.currency(line.openingBalance),
              colors,
            ),
            const SizedBox(height: ApexSpacing.xs),
            _mobileAmountRow(
              'Debit',
              line.totalDebits > 0 ? fmt.currency(line.totalDebits) : '—',
              colors,
            ),
            const SizedBox(height: ApexSpacing.xs),
            _mobileAmountRow(
              'Credit',
              line.totalCredits > 0 ? fmt.currency(line.totalCredits) : '—',
              colors,
            ),
            const Divider(height: ApexSpacing.lg),
            _mobileAmountRow(
              'Closing',
              fmt.currency(line.closingBalance),
              colors,
              strong: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileTotalsCard(
    TrialBalanceReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      padding: const EdgeInsets.all(ApexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Totals',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          _mobileAmountRow(
            'Opening',
            fmt.currency(
              report.totalOpeningDebits - report.totalOpeningCredits,
            ),
            colors,
            strong: true,
          ),
          const SizedBox(height: ApexSpacing.xs),
          _mobileAmountRow(
            'Debit',
            fmt.currency(report.totalDebits),
            colors,
            strong: true,
          ),
          const SizedBox(height: ApexSpacing.xs),
          _mobileAmountRow(
            'Credit',
            fmt.currency(report.totalCredits),
            colors,
            strong: true,
          ),
          const SizedBox(height: ApexSpacing.xs),
          _mobileAmountRow(
            'Closing',
            fmt.currency(
              report.totalClosingDebits - report.totalClosingCredits,
            ),
            colors,
            strong: true,
          ),
        ],
      ),
    );
  }

  Widget _desktopTotalsFooter(
    TrialBalanceReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
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
            flex: 36,
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
            flex: 16,
            child: MonetaryText(
              value: fmt.currency(
                report.totalOpeningDebits - report.totalOpeningCredits,
              ),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 16,
            child: MonetaryText(
              value: fmt.currency(report.totalDebits),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 16,
            child: MonetaryText(
              value: fmt.currency(report.totalCredits),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 16,
            child: MonetaryText(
              value: fmt.currency(
                report.totalClosingDebits - report.totalClosingCredits,
              ),
              fontSize: 14,
              fontWeight: FontWeight.w800,
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
          color: muted ? colors.textMuted : colors.textPrimary,
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _dash(ApexColors colors) {
    return Text(
      '—',
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 13, color: colors.textMuted),
    );
  }

  void _openAccountLedger(TrialBalanceLine line) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountLedgerScreen(
          accountId: line.accountId,
          accountName: line.accountName,
          accountCode: line.accountCode,
        ),
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
