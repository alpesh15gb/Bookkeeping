import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/search_bar.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../../trial_balance/models/trial_balance.dart';
import '../../trial_balance/services/trial_balance_service.dart';

final trialBalanceReportProvider =
    FutureProvider.autoDispose<TrialBalanceReport>((ref) async {
      final res = await ref
          .watch(trialBalanceServiceProvider)
          .getTrialBalance();
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

class TrialBalanceScreen extends ConsumerStatefulWidget {
  const TrialBalanceScreen({super.key});
  @override
  ConsumerState<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends ConsumerState<TrialBalanceScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(trialBalanceReportProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          const PageHeader(
            title: 'Trial Balance',
            subtitle: 'Real-time double-entry ledger verification.',
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 4),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(trialBalanceReportProvider),
              ),
              data: (report) {
                final q = _search.trim().toLowerCase();
                final lines = q.isEmpty
                    ? report.lines
                    : report.lines
                          .where(
                            (l) =>
                                l.accountName.toLowerCase().contains(q) ||
                                l.accountCode.toLowerCase().contains(q),
                          )
                          .toList();
                return Column(
                  children: [
                    _banner(report, colors),
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

  Widget _banner(TrialBalanceReport report, ApexColors colors) {
    final ok = report.isBalanced;
    final isMobile = ResponsiveLayout.isMobile(context);
    return Container(
      margin: EdgeInsets.fromLTRB(
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        ApexSpacing.xs,
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        ApexSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ApexSpacing.lg,
        vertical: ApexSpacing.md,
      ),
      decoration: BoxDecoration(
        color: (ok ? colors.success : colors.danger).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ApexRadius_md),
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
          Text(
            ok ? 'Ledgers are balanced' : 'Ledger out of balance',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ok ? colors.success : colors.danger,
            ),
          ),
        ],
      ),
    );
  }

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
          // Sticky header
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.lg,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(flex: 56, child: Text('ACCOUNT', style: _th(colors))),
                Expanded(
                  flex: 22,
                  child: Text(
                    'DEBIT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 22,
                  child: Text(
                    'CREDIT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 0),
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
                      final l = lines[i];
                      return Container(
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
                              flex: 56,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      l.accountCode,
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
                                      l.accountName,
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
                              flex: 22,
                              child: Text(
                                l.totalDebits > 0
                                    ? fmt.currency(l.totalDebits)
                                    : '—',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: l.totalDebits > 0
                                      ? colors.textPrimary
                                      : colors.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 22,
                              child: Text(
                                l.totalCredits > 0
                                    ? fmt.currency(l.totalCredits)
                                    : '—',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: l.totalCredits > 0
                                      ? colors.textPrimary
                                      : colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // Totals footer
          Container(
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
                  flex: 56,
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
                  flex: 22,
                  child: Text(
                    fmt.currency(report.totalDebits),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 22,
                  child: Text(
                    fmt.currency(report.totalCredits),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
              ],
            ),
          );
        }

        final line = lines[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: ApexSpacing.md),
          child: ApexCard(
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
              ],
            ),
          ),
        );
      },
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

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
