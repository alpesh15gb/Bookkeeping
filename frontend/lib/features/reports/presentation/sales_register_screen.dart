/// Sales Register screen — list of all sales invoices in a date range.
///
/// Mirrors the TrialBalanceScreen / ProfitLossScreen layout pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/report_models.dart';
import '../services/reports_service.dart';

// ---------------------------------------------------------------------------
// Riverpod state — date-range filters drive the API call.
// ---------------------------------------------------------------------------

final srDateFromProvider = StateProvider<String?>((ref) => null);
final srDateToProvider = StateProvider<String?>((ref) => null);

final salesRegisterProvider =
    FutureProvider.autoDispose<List<SalesTransaction>>((ref) async {
  final dateFrom = ref.watch(srDateFromProvider);
  final dateTo = ref.watch(srDateToProvider);
  final res = await ref
      .watch(reportsServiceProvider)
      .getSalesTransactions(dateFrom: dateFrom, dateTo: dateTo);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SalesRegisterScreen extends ConsumerStatefulWidget {
  const SalesRegisterScreen({super.key});
  @override
  ConsumerState<SalesRegisterScreen> createState() =>
      _SalesRegisterScreenState();
}

class _SalesRegisterScreenState extends ConsumerState<SalesRegisterScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    // Write initial dates so the first load uses them.
    Future.microtask(() {
      ref.read(srDateFromProvider.notifier).state = _toApiDate(_fromDate!);
      ref.read(srDateToProvider.notifier).state = _toApiDate(_toDate!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(salesRegisterProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Sales Register',
            subtitle: 'All sales invoices for the selected period.',
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
                      TableRowSkeleton(columns: 5),
                    ],
                  ),
                ),
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(salesRegisterProvider),
              ),
              data: (transactions) {
                if (transactions.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No sales for this period',
                    subtitle: 'Try adjusting the date range.',
                  );
                }
                return _buildTable(transactions, colors, fmt);
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
        ref.read(srDateFromProvider.notifier).state = _toApiDate(picked);
      } else {
        _toDate = picked;
        ref.read(srDateToProvider.notifier).state = _toApiDate(picked);
      }
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _toApiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtDateShort(String isoDate) {
    if (isoDate.isEmpty) return '—';
    try {
      final parts = isoDate.split('-');
      if (parts.length == 3) {
        final d = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      }
    } catch (_) {}
    return isoDate;
  }

  // -----------------------------------------------------------------------
  // Data table
  // -----------------------------------------------------------------------

  Widget _buildTable(
    List<SalesTransaction> transactions,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final totalCount = transactions.length;
    final totalAmount = transactions.fold<double>(0, (s, t) => s + t.total);
    final totalTax = transactions.fold<double>(0, (s, t) => s + t.taxTotal);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        ApexSpacing.xl,
        0,
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
          // Sticky header
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.lg,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(flex: 14, child: Text('DATE', style: _th(colors))),
                Expanded(
                  flex: 20,
                  child: Text('INVOICE #', style: _th(colors)),
                ),
                Expanded(
                  flex: 28,
                  child: Text('CUSTOMER', style: _th(colors)),
                ),
                Expanded(
                  flex: 14,
                  child: Text(
                    'TOTAL',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 12,
                  child: Text(
                    'TAX',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 12,
                  child: Text(
                    'STATUS',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          // Scrollable rows
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: transactions.length,
              itemBuilder: (context, i) {
                final t = transactions[i];
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
                        flex: 14,
                        child: Text(
                          _fmtDateShort(t.issueDate),
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 20,
                        child: Text(
                          t.invoiceNumber,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 28,
                        child: Text(
                          t.customerName,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 14,
                        child: MonetaryText(
                          value: fmt.currency(t.total),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: MonetaryText(
                          value: fmt.currency(t.taxTotal),
                          fontSize: 12,
                          color: colors.textSecondary,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: StatusBadge(
                            label: t.status.replaceAll('_', ' '),
                            tone: toneForStatus(t.status),
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
              border: Border(
                top: BorderSide(color: colors.border, width: 1.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.lg,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 62,
                  child: Text(
                    'TOTAL  ·  $totalCount invoice${totalCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 14,
                  child: MonetaryText(
                    value: fmt.currency(totalAmount),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 12,
                  child: MonetaryText(
                    value: fmt.currency(totalTax),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                    textAlign: TextAlign.right,
                  ),
                ),
                const Expanded(flex: 12, child: SizedBox()),
              ],
            ),
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
