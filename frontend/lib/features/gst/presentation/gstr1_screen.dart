/// GSTR-1 report screen — tabbed view of B2B, B2C Large, B2C Small,
/// Credit/Debit Notes (registered + unregistered), and HSN summary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../services/gst_service.dart';
import '../models/gst_models.dart';

// ---------------------------------------------------------------------------
// Period state
// ---------------------------------------------------------------------------

final _gstr1PeriodProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

final _gstr1TabsProvider = StateProvider<int>((ref) => 0);

final _gstr1ReportProvider = FutureProvider.autoDispose<Gstr1Summary>((
  ref,
) async {
  final period = ref.watch(_gstr1PeriodProvider);
  final parts = period.split('-');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final lastDay = _daysInMonth(y, m);
  final res = await ref
      .read(gstServiceProvider)
      .getGstr1(startDate: '$period-01', endDate: '$period-$lastDay');
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

class Gstr1Screen extends ConsumerStatefulWidget {
  const Gstr1Screen({super.key});
  @override
  ConsumerState<Gstr1Screen> createState() => _Gstr1ScreenState();
}

class _Gstr1ScreenState extends ConsumerState<Gstr1Screen> {
  bool _downloading = false;

  ({String start, String end}) _periodDates() {
    final period = ref.read(_gstr1PeriodProvider);
    final parts = period.split('-');
    final days = _daysInMonth(int.parse(parts[0]), int.parse(parts[1]));
    return (
      start: '$period-01',
      end: '$period-${days.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _download(ExportKind kind) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final dates = _periodDates();
    final url = switch (kind) {
      ExportKind.json => '/gst/gstr1/offline-json',
      ExportKind.pdf => '/gst/gstr1/pdf',
      _ => '/gst/gstr1/export',
    };
    final result = await ref
        .read(downloadServiceProvider)
        .download(
          relativeUrl: url,
          filename: 'GSTR1_${ref.read(_gstr1PeriodProvider)}',
          kind: kind,
          queryParameters: {'start_date': dates.start, 'end_date': dates.end},
        );
    if (!mounted) return;
    setState(() => _downloading = false);
    final notifications = ref.read(notificationServiceProvider);
    switch (result) {
      case Success(:final value):
        notifications.success(
          context,
          'Saved to ${value.path}',
          title: 'GSTR-1 downloaded',
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
    final reportAsync = ref.watch(_gstr1ReportProvider);
    final tab = ref.watch(_gstr1TabsProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'GSTR-1',
            subtitle: 'Outward supply sales tax return detail.',
            actions: [
              OutlinedButton.icon(
                onPressed: _downloading
                    ? null
                    : () => _download(ExportKind.json),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('GST Offline JSON'),
              ),
              PopupMenuButton<ExportKind>(
                tooltip: 'Other exports',
                onSelected: _download,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: ExportKind.excel,
                    child: Text('Download Excel workbook'),
                  ),
                  PopupMenuItem(
                    value: ExportKind.pdf,
                    child: Text('Download PDF summary'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(Icons.download_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Export'),
                    ],
                  ),
                ),
              ),
              _periodSelector(colors),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: colors.info,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Import the JSON into the latest GST Returns Offline Tool, resolve its validation results, then upload to the GST portal. ApexBooks blocks export when HSN/SAC or place of supply is missing.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          _tabBar(colors, tab),
          Expanded(
            child: reportAsync.when(
              loading: () => const _ReportLoading(),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(_gstr1ReportProvider),
              ),
              data: (report) => _tabContent(report, tab, colors),
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
    final period = ref.watch(_gstr1PeriodProvider);
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
    final period = ref.read(_gstr1PeriodProvider);
    final parts = period.split('-');
    final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select month',
    );
    if (picked == null) return;
    ref.read(_gstr1PeriodProvider.notifier).state =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
    ref.read(_gstr1TabsProvider.notifier).state = 0;
  }

  // ---------------------------------------------------------------------------
  // Tab bar
  // ---------------------------------------------------------------------------

  Widget _tabBar(ApexColors colors, int currentTab) {
    final tabs = ['B2B', 'B2CL', 'B2CS', 'Notes', 'HSN'];
    return Container(
      color: colors.surfaceMuted,
      padding: const EdgeInsets.fromLTRB(
        ApexSpacing.xl,
        0,
        ApexSpacing.xl,
        ApexSpacing.sm,
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = i == currentTab;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => ref.read(_gstr1TabsProvider.notifier).state = i,
              borderRadius: BorderRadius.circular(ApexRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? colors.surfaceRaised : Colors.transparent,
                  borderRadius: BorderRadius.circular(ApexRadius.md),
                  border: Border.all(
                    color: selected ? colors.border : Colors.transparent,
                  ),
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab content
  // ---------------------------------------------------------------------------

  Widget _tabContent(Gstr1Summary report, int tab, ApexColors colors) {
    switch (tab) {
      case 0:
        return _b2bTable(report.b2b, colors);
      case 1:
        return _b2clTable(report.b2cl, colors);
      case 2:
        return _b2csTable(report.b2cs, colors);
      case 3:
        return _notesTable(report.cdnr, report.cdnur, colors);
      case 4:
        return _hsnTable(report.hsnSummary, colors);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // B2B table
  // ---------------------------------------------------------------------------

  Widget _b2bTable(List<Gstr1B2BLine> lines, ApexColors colors) {
    if (lines.isEmpty) {
      return _emptyTable('No B2B invoices for this period.', colors);
    }
    double totalTaxable = 0,
        totalCgst = 0,
        totalSgst = 0,
        totalIgst = 0,
        totalValue = 0;
    for (final l in lines) {
      totalTaxable += l.taxableValue;
      totalCgst += l.cgstAmount;
      totalSgst += l.sgstAmount;
      totalIgst += l.igstAmount;
      totalValue += l.totalValue;
    }
    return _detailTable(
      columns: [
        'GSTIN',
        'Customer',
        'Invoice#',
        'Date',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
        'Total',
      ],
      rows: lines,
      rowBuilder: (l, fmt) => [
        l.customerGstin,
        l.customerName,
        l.invoiceNumber,
        l.invoiceDate,
        fmt.currency(l.taxableValue),
        fmt.currency(l.cgstAmount),
        fmt.currency(l.sgstAmount),
        fmt.currency(l.igstAmount),
        fmt.currency(l.totalValue),
      ],
      footerBuilder: (fmt) => [
        '',
        '',
        '',
        'Total',
        fmt.currency(totalTaxable),
        fmt.currency(totalCgst),
        fmt.currency(totalSgst),
        fmt.currency(totalIgst),
        fmt.currency(totalValue),
      ],
      colors: colors,
    );
  }

  // ---------------------------------------------------------------------------
  // B2CL table
  // ---------------------------------------------------------------------------

  Widget _b2clTable(List<Gstr1B2CLLine> lines, ApexColors colors) {
    if (lines.isEmpty) {
      return _emptyTable('No B2C large invoices for this period.', colors);
    }
    double totalTaxable = 0, totalIgst = 0, totalValue = 0;
    for (final l in lines) {
      totalTaxable += l.taxableValue;
      totalIgst += l.igstAmount;
      totalValue += l.totalValue;
    }
    return _detailTable(
      columns: ['Invoice#', 'Date', 'POS Code', 'Taxable', 'IGST', 'Total'],
      rows: lines,
      rowBuilder: (l, fmt) => [
        l.invoiceNumber,
        l.invoiceDate,
        l.posStateCode,
        fmt.currency(l.taxableValue),
        fmt.currency(l.igstAmount),
        fmt.currency(l.totalValue),
      ],
      footerBuilder: (fmt) => [
        '',
        '',
        'Total',
        fmt.currency(totalTaxable),
        fmt.currency(totalIgst),
        fmt.currency(totalValue),
      ],
      colors: colors,
    );
  }

  // ---------------------------------------------------------------------------
  // B2CS table
  // ---------------------------------------------------------------------------

  Widget _b2csTable(List<Gstr1B2CSLine> lines, ApexColors colors) {
    if (lines.isEmpty) {
      return _emptyTable('No B2C supplies for this period.', colors);
    }
    double totalTaxable = 0, totalCgst = 0, totalSgst = 0, totalIgst = 0;
    for (final l in lines) {
      totalTaxable += l.taxableValue;
      totalCgst += l.cgstAmount;
      totalSgst += l.sgstAmount;
      totalIgst += l.igstAmount;
    }
    return _detailTable(
      columns: ['POS', 'Rate', 'Taxable', 'CGST', 'SGST', 'IGST'],
      rows: lines,
      rowBuilder: (l, fmt) => [
        l.posStateCode,
        fmt.percent(l.gstRate),
        fmt.currency(l.taxableValue),
        fmt.currency(l.cgstAmount),
        fmt.currency(l.sgstAmount),
        fmt.currency(l.igstAmount),
      ],
      footerBuilder: (fmt) => [
        '',
        '',
        fmt.currency(totalTaxable),
        fmt.currency(totalCgst),
        fmt.currency(totalSgst),
        fmt.currency(totalIgst),
      ],
      colors: colors,
    );
  }

  // ---------------------------------------------------------------------------
  // Notes table
  // ---------------------------------------------------------------------------

  Widget _notesTable(
    List<Gstr1NoteLine> cdnr,
    List<Gstr1NoteLine> cdnur,
    ApexColors colors,
  ) {
    final all = [...cdnr, ...cdnur];
    if (all.isEmpty) {
      return _emptyTable('No credit/debit notes for this period.', colors);
    }
    double totalTaxable = 0,
        totalCgst = 0,
        totalSgst = 0,
        totalIgst = 0,
        totalValue = 0;
    for (final l in all) {
      totalTaxable += l.taxableValue;
      totalCgst += l.cgstAmount;
      totalSgst += l.sgstAmount;
      totalIgst += l.igstAmount;
      totalValue += l.totalValue;
    }
    return _detailTable(
      columns: [
        'Note#',
        'Type',
        'Date',
        'GSTIN',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
        'Total',
      ],
      rows: all,
      rowBuilder: (l, fmt) => [
        l.noteNumber,
        l.noteType,
        l.noteDate,
        l.customerGstin ?? '—',
        fmt.currency(l.taxableValue),
        fmt.currency(l.cgstAmount),
        fmt.currency(l.sgstAmount),
        fmt.currency(l.igstAmount),
        fmt.currency(l.totalValue),
      ],
      footerBuilder: (fmt) => [
        '',
        '',
        '',
        'Total',
        fmt.currency(totalTaxable),
        fmt.currency(totalCgst),
        fmt.currency(totalSgst),
        fmt.currency(totalIgst),
        fmt.currency(totalValue),
      ],
      colors: colors,
    );
  }

  // ---------------------------------------------------------------------------
  // HSN summary table
  // ---------------------------------------------------------------------------

  Widget _hsnTable(List<Gstr1HSNLine> lines, ApexColors colors) {
    if (lines.isEmpty) {
      return _emptyTable('No HSN data for this period.', colors);
    }
    double totalQty = 0, totalValue = 0, totalTaxable = 0;
    double totalCgst = 0, totalSgst = 0, totalIgst = 0;
    for (final l in lines) {
      totalQty += l.totalQuantity;
      totalValue += l.totalValue;
      totalTaxable += l.taxableValue;
      totalCgst += l.cgstAmount;
      totalSgst += l.sgstAmount;
      totalIgst += l.igstAmount;
    }
    return _detailTable(
      columns: [
        'HSN/SAC',
        'Description',
        'UOM',
        'Qty',
        'Value',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
      ],
      rows: lines,
      rowBuilder: (l, fmt) => [
        l.hsnSac,
        l.description,
        l.uom,
        fmt.quantity(l.totalQuantity),
        fmt.currency(l.totalValue),
        fmt.currency(l.taxableValue),
        fmt.currency(l.cgstAmount),
        fmt.currency(l.sgstAmount),
        fmt.currency(l.igstAmount),
      ],
      footerBuilder: (fmt) => [
        '',
        '',
        '',
        fmt.quantity(totalQty),
        fmt.currency(totalValue),
        fmt.currency(totalTaxable),
        fmt.currency(totalCgst),
        fmt.currency(totalSgst),
        fmt.currency(totalIgst),
      ],
      colors: colors,
    );
  }

  // ---------------------------------------------------------------------------
  // Shared table widget
  // ---------------------------------------------------------------------------

  Widget _detailTable<T>({
    required List<String> columns,
    required List<T> rows,
    required List<String> Function(T, NumberFormatter) rowBuilder,
    required List<String> Function(NumberFormatter) footerBuilder,
    required ApexColors colors,
  }) {
    final fmt = ref.watch(numberFormatterProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        ApexSpacing.xl,
        ApexSpacing.sm,
        ApexSpacing.xl,
        ApexSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.lg,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: List.generate(columns.length, (i) {
                return Expanded(
                  child: Text(
                    columns[i].toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: colors.textMuted,
                    ),
                    textAlign: i == 0 ? TextAlign.start : TextAlign.right,
                  ),
                );
              }),
            ),
          ),
          // Rows
          if (rows.isEmpty)
            SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  'No data',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
            )
          else
            SizedBox(
              height: 400,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rowBuilder(rows[i], fmt);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ApexSpacing.lg,
                      vertical: ApexSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: colors.border)),
                    ),
                    child: Row(
                      children: List.generate(row.length, (j) {
                        return Expanded(
                          child: Text(
                            row[j],
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                            textAlign: j == 0
                                ? TextAlign.start
                                : TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          // Footer
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
              children: List.generate(footerBuilder(fmt).length, (i) {
                final cell = footerBuilder(fmt)[i];
                return Expanded(
                  child: Text(
                    cell,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                    textAlign: i == 0 ? TextAlign.start : TextAlign.right,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTable(String message, ApexColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ApexSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: colors.textMuted),
            const SizedBox(height: ApexSpacing.md),
            Text(
              message,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

class _ReportLoading extends StatelessWidget {
  const _ReportLoading();

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          ApexSpacing.xl,
          ApexSpacing.sm,
          ApexSpacing.xl,
          ApexSpacing.lg,
        ),
        padding: const EdgeInsets.all(ApexSpacing.lg),
        decoration: BoxDecoration(
          color: apexColors(context).skeletonBase,
          borderRadius: BorderRadius.circular(ApexRadius.lg),
        ),
        child: Column(
          children: List.generate(
            6,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: List.generate(
                  5,
                  (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: const SkeletonBox(height: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
