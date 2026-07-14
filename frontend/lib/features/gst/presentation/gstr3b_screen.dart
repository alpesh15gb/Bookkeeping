/// GSTR-3B monthly return screen — Table 3.1 (outward supplies),
/// Table 4 (ITC), and Net Tax Payable calculation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import '../services/gst_service.dart';
import '../models/gst_models.dart';

// ---------------------------------------------------------------------------
// Period state
// ---------------------------------------------------------------------------

final _gstr3bPeriodProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

final _gstr3bReportProvider = FutureProvider.autoDispose<Gstr3BSummary>((
  ref,
) async {
  final period = ref.watch(_gstr3bPeriodProvider);
  final parts = period.split('-');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final lastDay = _daysInMonth(y, m);
  final res = await ref
      .read(gstServiceProvider)
      .getGstr3b(startDate: '$period-01', endDate: '$period-$lastDay');
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

class Gstr3bScreen extends ConsumerStatefulWidget {
  const Gstr3bScreen({super.key});
  @override
  ConsumerState<Gstr3bScreen> createState() => _Gstr3bScreenState();
}

class _Gstr3bScreenState extends ConsumerState<Gstr3bScreen> {
  bool _downloading = false;

  Future<void> _download(ExportKind kind) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final period = ref.read(_gstr3bPeriodProvider);
    final parts = period.split('-');
    final days = _daysInMonth(int.parse(parts[0]), int.parse(parts[1]));
    final result = await ref
        .read(downloadServiceProvider)
        .download(
          relativeUrl: kind == ExportKind.pdf
              ? '/gst/gstr3b/pdf'
              : '/gst/gstr3b/export',
          filename: 'GSTR3B_Working_${period}',
          kind: kind,
          queryParameters: {
            'start_date': '$period-01',
            'end_date': '$period-${days.toString().padLeft(2, '0')}',
          },
        );
    if (!mounted) return;
    setState(() => _downloading = false);
    final notifications = ref.read(notificationServiceProvider);
    switch (result) {
      case Success(:final value):
        notifications.success(
          context,
          'Saved to ${value.path}',
          title: 'GSTR-3B downloaded',
        );
      case Failure(:final error):
        notifications.error(context, error.message, title: 'Download failed');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final asyncVal = ref.watch(_gstr3bReportProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'GSTR-3B',
            subtitle: 'Monthly consolidated GST summary return.',
            actions: [
              OutlinedButton.icon(
                onPressed: _downloading
                    ? null
                    : () => _download(ExportKind.excel),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Working Excel'),
              ),
              OutlinedButton.icon(
                onPressed: _downloading
                    ? null
                    : () => _download(ExportKind.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
              _periodSelector(colors),
            ],
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => const _Gstr3bLoading(),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(_gstr3bReportProvider),
              ),
              data: (report) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  ApexSpacing.xl,
                  ApexSpacing.sm,
                  ApexSpacing.xl,
                  ApexSpacing.xxl,
                ),
                child: Column(
                  children: [
                    _table31(report, colors),
                    const SizedBox(height: ApexSpacing.lg),
                    _table4(report, colors),
                    const SizedBox(height: ApexSpacing.lg),
                    _netPayable(report, colors),
                    const SizedBox(height: ApexSpacing.lg),
                    _filingSummary(report, colors),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Period selector
  // ---------------------------------------------------------------------------

  Widget _periodSelector(ApexColors colors) {
    final period = ref.watch(_gstr3bPeriodProvider);
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return InkWell(
      onTap: _pickPeriod,
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
    final period = ref.read(_gstr3bPeriodProvider);
    final parts = period.split('-');
    final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    ref.read(_gstr3bPeriodProvider.notifier).state =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Table 3.1: Outward Supplies
  // ---------------------------------------------------------------------------

  Widget _table31(Gstr3BSummary report, ApexColors colors) {
    final fmt = ref.watch(numberFormatterProvider);
    final out = report.outwardTaxableSupplies;
    final nil = report.nilRatedSupplies;

    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Table 3.1: Outward Supplies',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.sm),
          Text(
            'Taxable, nil-rated, and exempted outward supplies',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: ApexSpacing.md),
          Divider(height: 1, color: colors.border),
          _sectionHeader([
            'Nature of Supplies',
            'Taxable Value',
            'IGST',
            'CGST',
            'SGST',
            'Cess',
          ], colors),
          Divider(height: 1, color: colors.border),
          _dataRow([
            '(a) Outward taxable supplies',
            fmt.currency(out.taxableValue),
            fmt.currency(out.integratedTax),
            fmt.currency(out.centralTax),
            fmt.currency(out.stateUtTax),
            fmt.currency(out.cess),
          ], colors),
          _dataRow(['(b) Zero rated', '—', '—', '—', '—', '—'], colors),
          _dataRow(
            [
              '(c) Nil rated / exempted',
              fmt.currency(nil.taxableValue),
              '—',
              '—',
              '—',
              '—',
            ],
            colors,
            muted: true,
          ),
          _dataRow(['(d) Reverse charge', '—', '—', '—', '—', '—'], colors),
          _dataRow(['(e) Non-GST', '—', '—', '—', '—', '—'], colors),
          Divider(height: 1, color: colors.border),
          _totalRow([
            'Total',
            fmt.currency(out.taxableValue + nil.taxableValue),
            fmt.currency(out.integratedTax),
            fmt.currency(out.centralTax),
            fmt.currency(out.stateUtTax),
            fmt.currency(out.cess),
          ], colors),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table 4: ITC
  // ---------------------------------------------------------------------------

  Widget _table4(Gstr3BSummary report, ApexColors colors) {
    final fmt = ref.watch(numberFormatterProvider);
    final itc = report.inwardSuppliesItc;

    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Table 4: Input Tax Credit',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.sm),
          Text(
            'ITC available, reversed, and net claimable',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: ApexSpacing.md),
          Divider(height: 1, color: colors.border),
          _sectionHeader([
            'ITC Details',
            'IGST',
            'CGST',
            'SGST',
            'Cess',
          ], colors),
          Divider(height: 1, color: colors.border),
          _groupHeader('(A) ITC Available', colors),
          _dataRow(
            ['  (1) Import of goods', '—', '—', '—', '—'],
            colors,
            muted: true,
          ),
          _dataRow(
            ['  (2) Import of services', '—', '—', '—', '—'],
            colors,
            muted: true,
          ),
          _dataRow(
            ['  (3) Reverse charge', '—', '—', '—', '—'],
            colors,
            muted: true,
          ),
          _dataRow(['  (4) ISD', '—', '—', '—', '—'], colors, muted: true),
          _dataRow([
            '  (5) All other ITC',
            fmt.currency(itc.integratedTax),
            fmt.currency(itc.centralTax),
            fmt.currency(itc.stateUtTax),
            fmt.currency(itc.cess),
          ], colors),
          _groupHeader('(B) ITC Reversed', colors),
          _dataRow(
            ['  (1) As per rules', '—', '—', '—', '—'],
            colors,
            muted: true,
          ),
          _dataRow(['  (2) Others', '—', '—', '—', '—'], colors, muted: true),
          Divider(height: 1, color: colors.border),
          _totalRow([
            '(C) Net ITC Available',
            fmt.currency(itc.integratedTax),
            fmt.currency(itc.centralTax),
            fmt.currency(itc.stateUtTax),
            fmt.currency(itc.cess),
          ], colors),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Net Tax Payable
  // ---------------------------------------------------------------------------

  Widget _netPayable(Gstr3BSummary report, ApexColors colors) {
    final fmt = ref.watch(numberFormatterProvider);
    final out = report.outwardTaxableSupplies;
    final itc = report.inwardSuppliesItc;

    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_rounded,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Net Tax Payable',
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
          _sectionHeader([
            'Tax Head',
            'Output Tax',
            'ITC Claimed',
            'Net Payable',
          ], colors),
          Divider(height: 1, color: colors.border),
          _dataRow([
            'IGST',
            fmt.currency(out.integratedTax),
            fmt.currency(itc.integratedTax),
            _netCell(report.netTaxPayableIgst, fmt),
          ], colors),
          _dataRow([
            'CGST',
            fmt.currency(out.centralTax),
            fmt.currency(itc.centralTax),
            _netCell(report.netTaxPayableCgst, fmt),
          ], colors),
          _dataRow([
            'SGST',
            fmt.currency(out.stateUtTax),
            fmt.currency(itc.stateUtTax),
            _netCell(report.netTaxPayableSgst, fmt),
          ], colors),
          _dataRow([
            'Cess',
            fmt.currency(out.cess),
            fmt.currency(itc.cess),
            _netCell(report.netTaxPayableCess, fmt),
          ], colors),
          Divider(height: 1, color: colors.border),
          _totalRow([
            'Total',
            fmt.currency(
              out.integratedTax + out.centralTax + out.stateUtTax + out.cess,
            ),
            fmt.currency(
              itc.integratedTax + itc.centralTax + itc.stateUtTax + itc.cess,
            ),
            fmt.currency(report.netTaxPayable),
          ], colors),
        ],
      ),
    );
  }

  String _netCell(double value, NumberFormatter fmt) {
    return value > 0 ? fmt.currency(value) : '—';
  }

  // ---------------------------------------------------------------------------
  // Filing summary
  // ---------------------------------------------------------------------------

  Widget _filingSummary(Gstr3BSummary report, ApexColors colors) {
    return ApexCard(
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: colors.info),
          const SizedBox(width: ApexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filing Due Date',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review the GST portal for the applicable monthly/QRMP due date. Verify this working against portal-generated GSTR-2B before filing.',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(ApexRadius.md),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              report.gstin ?? 'No GSTIN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared row builders
  // ---------------------------------------------------------------------------

  Widget _sectionHeader(List<String> cells, ApexColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
      child: Row(
        children: cells
            .map(
              (c) => Expanded(
                child: Text(
                  c.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: colors.textMuted,
                  ),
                  textAlign: _align(cells.indexOf(c), cells.length),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _groupHeader(String label, ApexColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(List<String> cells, ApexColors colors, {bool muted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: cells.map((c) {
          final i = cells.indexOf(c);
          return Expanded(
            child: Text(
              c,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: muted ? FontWeight.w400 : FontWeight.w500,
                color: muted ? colors.textMuted : colors.textPrimary,
              ),
              textAlign: _align(i, cells.length),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _totalRow(List<String> cells, ApexColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ApexSpacing.md),
      child: Row(
        children: cells.map((c) {
          final i = cells.indexOf(c);
          return Expanded(
            child: Text(
              c,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
              textAlign: _align(i, cells.length),
            ),
          );
        }).toList(),
      ),
    );
  }

  TextAlign _align(int index, int total) {
    return index == 0 ? TextAlign.start : TextAlign.right;
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

class _Gstr3bLoading extends StatelessWidget {
  const _Gstr3bLoading();

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ShimmerSkeleton(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ApexSpacing.xl,
          ApexSpacing.sm,
          ApexSpacing.xl,
          ApexSpacing.xxl,
        ),
        child: Column(
          children: [
            for (int c = 0; c < 3; c++) ...[
              Container(
                padding: const EdgeInsets.all(ApexSpacing.lg),
                decoration: BoxDecoration(
                  color: colors.skeletonBase,
                  borderRadius: BorderRadius.circular(ApexRadius.lg),
                ),
                child: Column(
                  children: List.generate(
                    5,
                    (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: List.generate(
                          3,
                          (i) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                              child: SkeletonBox(height: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ApexSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }
}
