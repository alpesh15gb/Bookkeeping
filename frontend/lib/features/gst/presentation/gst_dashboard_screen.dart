/// GST Dashboard — period overview with KPI cards, GSTR-1 / GSTR-3B
/// summaries, and recent return-filing status.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/presentation/design_system/tokens/app_spacing.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../services/gst_service.dart';
import '../models/gst_models.dart';

// ---------------------------------------------------------------------------
// Period state
// ---------------------------------------------------------------------------

final _gstPeriodProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

final _gstDashboardGstr1Provider = FutureProvider.autoDispose<Gstr1Summary>((
  ref,
) async {
  final period = ref.watch(_gstPeriodProvider);
  final parts = period.split('-');
  final res = await ref
      .read(gstServiceProvider)
      .getGstr1(
        startDate: '$period-01',
        endDate:
            '${parts[0]}-${parts[1]}-${_daysInMonth(int.parse(parts[0]), int.parse(parts[1]))}',
      );
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

final _gstDashboardGstr3bProvider = FutureProvider.autoDispose<Gstr3BSummary>((
  ref,
) async {
  final period = ref.watch(_gstPeriodProvider);
  final parts = period.split('-');
  final res = await ref
      .read(gstServiceProvider)
      .getGstr3b(
        startDate: '$period-01',
        endDate:
            '${parts[0]}-${parts[1]}-${_daysInMonth(int.parse(parts[0]), int.parse(parts[1]))}',
      );
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

final _gstDashboardReturnsProvider =
    FutureProvider.autoDispose<List<GstReturn>>((ref) async {
      final res = await ref.read(gstServiceProvider).listReturns();
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

int _daysInMonth(int year, int month) {
  if (month == 2) {
    if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) return 29;
    return 28;
  }
  if ([4, 6, 9, 11].contains(month)) return 30;
  return 31;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GstDashboardScreen extends ConsumerStatefulWidget {
  const GstDashboardScreen({super.key});
  @override
  ConsumerState<GstDashboardScreen> createState() => _GstDashboardScreenState();
}

class _GstDashboardScreenState extends ConsumerState<GstDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final gstr1Async = ref.watch(_gstDashboardGstr1Provider);
    final gstr3bAsync = ref.watch(_gstDashboardGstr3bProvider);
    final returnsAsync = ref.watch(_gstDashboardReturnsProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ApexSpacing.xl,
          0,
          ApexSpacing.xl,
          ApexSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'GST Dashboard',
              subtitle: 'Period overview and compliance status.',
              actions: [_periodSelector(colors)],
            ),
            const SizedBox(height: ApexSpacing.sm),
            // KPI row
            gstr3bAsync.when(
              loading: () => _kpiSkeleton(colors),
              error: (_, _) => const SizedBox.shrink(),
              data: (gstr3b) => _kpiRow(gstr3b, colors, fmt),
            ),
            const SizedBox(height: ApexSpacing.lg),
            // GSTR-1 + GSTR-3B summaries side by side
            LayoutBuilder(
              builder: (context, c) {
                final twoCol = c.maxWidth >= 900;
                if (twoCol) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _gstr1Card(gstr1Async, colors, fmt)),
                      const SizedBox(width: ApexSpacing.lg),
                      Expanded(child: _gstr3bCard(gstr3bAsync, colors, fmt)),
                    ],
                  );
                }
                return Column(
                  children: [
                    _gstr1Card(gstr1Async, colors, fmt),
                    const SizedBox(height: ApexSpacing.lg),
                    _gstr3bCard(gstr3bAsync, colors, fmt),
                  ],
                );
              },
            ),
            const SizedBox(height: ApexSpacing.lg),
            // Recent returns
            _recentReturnsCard(returnsAsync, colors, fmt),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Period selector
  // ---------------------------------------------------------------------------

  Widget _periodSelector(ApexColors colors) {
    final period = ref.watch(_gstPeriodProvider);
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    const months = [
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
    return InkWell(
      onTap: () => _pickPeriod(),
      borderRadius: BorderRadius.circular(ApexRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              '${months[month - 1]} $year',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.unfold_more_rounded, size: 14, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPeriod() async {
    final period = ref.read(_gstPeriodProvider);
    final parts = period.split('-');
    final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select a month',
    );
    if (picked == null) return;
    ref.read(_gstPeriodProvider.notifier).state =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // KPI row
  // ---------------------------------------------------------------------------

  Widget _kpiRow(Gstr3BSummary gstr3b, ApexColors colors, NumberFormatter fmt) {
    final outputGst = gstr3b.outwardTaxableSupplies;
    final itc = gstr3b.inwardSuppliesItc;
    final outputTotal =
        outputGst.integratedTax + outputGst.centralTax + outputGst.stateUtTax;
    final inputTotal = itc.integratedTax + itc.centralTax + itc.stateUtTax;
    final netPayable = outputTotal - inputTotal;

    return Row(
      children: [
        _kpiCard(
          label: 'Output GST',
          value: fmt.currency(outputTotal),
          icon: Icons.arrow_upward_rounded,
          color: colors.warning,
          colors: colors,
        ),
        const SizedBox(width: ApexSpacing.md),
        _kpiCard(
          label: 'Input GST (ITC)',
          value: fmt.currency(inputTotal),
          icon: Icons.arrow_downward_rounded,
          color: colors.info,
          colors: colors,
        ),
        const SizedBox(width: ApexSpacing.md),
        _kpiCard(
          label: 'Net Payable',
          value: fmt.currency(netPayable),
          icon: Icons.account_balance_rounded,
          color: netPayable > 0 ? colors.danger : colors.success,
          colors: colors,
          emphasize: true,
        ),
      ],
    );
  }

  Widget _kpiSkeleton(ApexColors colors) {
    return Row(
      children: List.generate(
        3,
        (_) => Expanded(
          child: ShimmerSkeleton(
            child: Container(
              height: 80,
              margin: const EdgeInsets.only(right: ApexSpacing.md),
              decoration: BoxDecoration(
                color: colors.skeletonBase,
                borderRadius: BorderRadius.circular(ApexRadius.lg),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required ApexColors colors,
    bool emphasize = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(ApexSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
          border: Border.all(
            color: emphasize ? color.withValues(alpha: 0.4) : colors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ApexRadius.sm),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: ApexSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  MonetaryText(
                    value: value,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GSTR-1 summary card
  // ---------------------------------------------------------------------------

  Widget _gstr1Card(
    AsyncValue<Gstr1Summary> asyncVal,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      child: asyncVal.when(
        loading: () => ShimmerSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 120, height: 16),
              const SizedBox(height: AppSpacing.lg),
              for (int i = 0; i < 4; i++) ...[
                const Row(
                  children: [
                    SkeletonBox(width: 100, height: 12),
                    Spacer(),
                    SkeletonBox(width: 80, height: 12),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(_gstDashboardGstr1Provider),
        ),
        data: (summary) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'GSTR-1 Summary',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ApexSpacing.md),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: ApexSpacing.sm),
            _summaryRow(
              'B2B Invoices',
              '${summary.b2b.length}',
              fmt.currency(summary.totalTaxableValue),
              colors,
            ),
            _summaryRow(
              'B2C Large',
              '${summary.b2cl.length}',
              fmt.currency(summary.totalIgst),
              colors,
            ),
            _summaryRow(
              'Credit/Debit Notes',
              '${summary.cdnr.length + summary.cdnur.length}',
              fmt.currency(summary.totalCgst + summary.totalSgst),
              colors,
            ),
            const SizedBox(height: ApexSpacing.sm),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: ApexSpacing.sm),
            _summaryRow(
              'Total Output GST',
              '',
              fmt.currency(summary.totalOutputGst),
              colors,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String count,
    String value,
    ApexColors colors, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                if (count.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(ApexRadius.pill),
                    ),
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          MonetaryText(
            value: value,
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: colors.textPrimary,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GSTR-3B summary card
  // ---------------------------------------------------------------------------

  Widget _gstr3bCard(
    AsyncValue<Gstr3BSummary> asyncVal,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      child: asyncVal.when(
        loading: () => ShimmerSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 120, height: 16),
              const SizedBox(height: AppSpacing.lg),
              for (int i = 0; i < 4; i++) ...[
                const Row(
                  children: [
                    SkeletonBox(width: 100, height: 12),
                    Spacer(),
                    SkeletonBox(width: 80, height: 12),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(_gstDashboardGstr3bProvider),
        ),
        data: (gstr3b) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize_rounded, size: 18, color: colors.info),
                const SizedBox(width: 8),
                Text(
                  'GSTR-3B Summary',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ApexSpacing.md),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: ApexSpacing.sm),
            _summaryRow(
              'Taxable Supplies',
              '',
              fmt.currency(gstr3b.outwardTaxableSupplies.taxableValue),
              colors,
            ),
            _summaryRow(
              'Nil Rated',
              '',
              fmt.currency(gstr3b.nilRatedSupplies.taxableValue),
              colors,
            ),
            _summaryRow(
              'ITC Available',
              '',
              fmt.currency(gstr3b.totalItc),
              colors,
            ),
            const SizedBox(height: ApexSpacing.sm),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: ApexSpacing.sm),
            _summaryRow(
              'Net Tax Payable',
              '',
              fmt.currency(gstr3b.netTaxPayable),
              colors,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recent returns card
  // ---------------------------------------------------------------------------

  Widget _recentReturnsCard(
    AsyncValue<List<GstReturn>> asyncVal,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      child: asyncVal.when(
        loading: () => ShimmerSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 140, height: 16),
              const SizedBox(height: AppSpacing.lg),
              for (int i = 0; i < 3; i++) ...[
                const Row(
                  children: [
                    SkeletonBox(width: 100, height: 14),
                    Spacer(),
                    SkeletonBox(width: 60, height: 22),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(_gstDashboardReturnsProvider),
        ),
        data: (returns) {
          final sorted = [...returns]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final recent = sorted.take(5).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.assignment_rounded,
                    size: 18,
                    color: colors.success,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recent GST Returns',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${returns.length} total',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: ApexSpacing.md),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: ApexSpacing.lg),
                  child: Center(
                    child: Text(
                      'No returns filed yet',
                      style: TextStyle(color: colors.textMuted, fontSize: 13),
                    ),
                  ),
                )
              else
                ...recent.map((r) => _returnRow(r, colors)),
            ],
          );
        },
      ),
    );
  }

  Widget _returnRow(GstReturn r, ApexColors colors) {
    return Container(
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
                  '${r.returnType} · ${r.periodLabel}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (r.arn != null)
                  Text(
                    'ARN: ${r.arn}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          _statusBadge(r.status, colors),
        ],
      ),
    );
  }

  Widget _statusBadge(String status, ApexColors colors) {
    final (label, tone) = switch (status.toUpperCase()) {
      'DRAFT' => ('Draft', StatusTone.neutral),
      'READY' => ('Ready', StatusTone.info),
      'FILED' => ('Filed', StatusTone.success),
      'REVISED' => ('Revised', StatusTone.warning),
      _ => (status, StatusTone.neutral),
    };
    return StatusBadge(label: label, tone: tone);
  }
}
