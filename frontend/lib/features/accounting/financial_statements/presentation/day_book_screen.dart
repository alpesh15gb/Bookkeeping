/// Day Book report screen — shows all journal entries for a period.
///
/// Displays a chronological, searchable list of journal entry lines with
/// columns: Date, Particular (account), Voucher Type, Debit, and Credit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/search_bar.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/day_book.dart';
import '../services/financial_statement_service.dart';

// ---------------------------------------------------------------------------
// Riverpod state — date-range filters drive the API call.
// ---------------------------------------------------------------------------

final dayBookDateFromProvider = StateProvider<String?>((ref) => null);
final dayBookDateToProvider = StateProvider<String?>((ref) => null);

final dayBookReportProvider =
    FutureProvider.autoDispose<DayBookReport>((ref) async {
  final dateFrom = ref.watch(dayBookDateFromProvider);
  final dateTo = ref.watch(dayBookDateToProvider);
  final res = await ref
      .watch(financialStatementServiceProvider)
      .getDayBook(startDate: dateFrom, endDate: dateTo);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DayBookScreen extends ConsumerStatefulWidget {
  const DayBookScreen({super.key});
  @override
  ConsumerState<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends ConsumerState<DayBookScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(dayBookReportProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Day Book',
            subtitle: 'Chronological record of all journal entries.',
            actions: [_buildDateFilter(colors)],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ApexSpacing.xl, 0, ApexSpacing.xl, ApexSpacing.sm),
            child: ApexSearchBar(
              controller: _searchCtrl,
              hintText: 'Search account name…',
              onChanged: (v) => setState(() => _search = v),
            ),
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
                message: err.toString(),
                onRetry: () => ref.invalidate(dayBookReportProvider),
              ),
              data: (report) {
                if (report.entries.isEmpty) {
                  return const EmptyState(
                    icon: Icons.book_rounded,
                    title: 'No entries for this period',
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
            Icon(Icons.date_range_rounded,
                size: 14, color: colors.textSecondary),
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
        ref.read(dayBookDateFromProvider.notifier).state = _toApiDate(picked);
      } else {
        _toDate = picked;
        ref.read(dayBookDateToProvider.notifier).state = _toApiDate(picked);
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
    DayBookReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final rows = _flattenEntries(report);

    return Container(
      margin: const EdgeInsets.fromLTRB(
          ApexSpacing.xl, 0, ApexSpacing.xl, ApexSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Sticky header
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
                horizontal: ApexSpacing.lg, vertical: ApexSpacing.md),
            child: Row(
              children: [
                Expanded(flex: 18, child: Text('DATE', style: _th(colors))),
                Expanded(flex: 30,
                    child: Text('PARTICULAR', style: _th(colors))),
                Expanded(flex: 20,
                    child: Text('VOUCHER TYPE', style: _th(colors))),
                Expanded(
                  flex: 18,
                  child: Text('DEBIT',
                      textAlign: TextAlign.right, style: _th(colors)),
                ),
                Expanded(
                  flex: 18,
                  child: Text('CREDIT',
                      textAlign: TextAlign.right, style: _th(colors)),
                ),
              ],
            ),
          ),
          // Rows
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching entries',
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      return Container(
                        decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: colors.border)),
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
                                row.date,
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
                              flex: 30,
                              child: Text(
                                row.particular,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 20,
                              child: Text(
                                row.voucherType,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 18,
                              child: MonetaryText(
                                value: row.debit > 0
                                    ? fmt.currency(row.debit)
                                    : '—',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: row.debit > 0
                                    ? colors.textPrimary
                                    : colors.textMuted,
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 18,
                              child: MonetaryText(
                                value: row.credit > 0
                                    ? fmt.currency(row.credit)
                                    : '—',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: row.credit > 0
                                    ? colors.textPrimary
                                    : colors.textMuted,
                                textAlign: TextAlign.right,
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
              border:
                  Border(top: BorderSide(color: colors.border, width: 1.5)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.lg,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 68,
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
                    value: fmt.currency(report.totalDebit),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 18,
                  child: MonetaryText(
                    value: fmt.currency(report.totalCredit),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /// Flattens DayBook entries into display rows. First line of each entry
  /// carries the date and voucher type; subsequent lines only show account
  /// data. Filters by [account] name when [_search] is non-empty.
  List<_DayBookRow> _flattenEntries(DayBookReport report) {
    final q = _search.trim().toLowerCase();
    final rows = <_DayBookRow>[];

    for (final entry in report.entries) {
      bool isFirstLine = true;
      for (final line in entry.lines) {
        final particular = '${line.accountName} (${line.accountCode})';

        // Apply search filter
        if (q.isNotEmpty &&
            !particular.toLowerCase().contains(q)) {
          continue;
        }

        rows.add(_DayBookRow(
          date: isFirstLine ? _shortDate(entry.entryDate) : '',
          particular: particular,
          voucherType: isFirstLine ? entry.sourceType : '',
          debit: line.isDebit ? line.amount : 0,
          credit: !line.isDebit ? line.amount : 0,
        ));
        isFirstLine = false;
      }
    }
    return rows;
  }

  /// Converts YYYY-MM-DD to DD/MM/YYYY for the date column.
  static String _shortDate(String isoDate) {
    if (isoDate.length >= 10) {
      final parts = isoDate.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
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
// Internal display row for flattened day book entries.
// ---------------------------------------------------------------------------

class _DayBookRow {
  const _DayBookRow({
    required this.date,
    required this.particular,
    required this.voucherType,
    this.debit = 0,
    this.credit = 0,
  });

  final String date;
  final String particular;
  final String voucherType;
  final double debit;
  final double credit;
}
