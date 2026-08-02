/// Account Ledger screen — full transaction history for a single account.
///
/// Shows opening/closing balances with a paginated list of journal-entry lines.
/// Uses [LedgerService.getAccountLedger] for server-side paginated data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart' hide ApexCard;
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../models/ledger_report.dart';
import '../models/ledger_line.dart';
import '../services/ledger_service.dart';

// ---------------------------------------------------------------------------
// Query object used as the family key for the ledger report provider.
// ---------------------------------------------------------------------------

@immutable
class _AccountLedgerQuery {
  const _AccountLedgerQuery({
    required this.accountId,
    this.fromDate,
    this.toDate,
    this.page = 1,
  });

  final String accountId;
  final String? fromDate;
  final String? toDate;
  final int page;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AccountLedgerQuery &&
          accountId == other.accountId &&
          fromDate == other.fromDate &&
          toDate == other.toDate &&
          page == other.page;

  @override
  int get hashCode => Object.hash(accountId, fromDate, toDate, page);
}

// ---------------------------------------------------------------------------
// Riverpod provider — family keyed by query so every filter/page change
// triggers a fresh API call.
// ---------------------------------------------------------------------------

final accountLedgerReportProvider = FutureProvider.autoDispose
    .family<LedgerReport, _AccountLedgerQuery>((ref, query) async {
      final res = await ref
          .watch(ledgerServiceProvider)
          .getAccountLedger(
            accountId: query.accountId,
            fromDate: query.fromDate,
            toDate: query.toDate,
            page: query.page,
          );
      return switch (res) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
        _ => throw Exception(),
      };
    });

/// Page size used for server-side pagination — must match the service default.
const int _pageLimit = 100;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AccountLedgerScreen extends ConsumerStatefulWidget {
  const AccountLedgerScreen({
    super.key,
    required this.accountId,
    this.accountName = '',
    this.accountCode = '',
  });

  final String accountId;
  final String accountName;
  final String accountCode;

  @override
  ConsumerState<AccountLedgerScreen> createState() =>
      _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends ConsumerState<AccountLedgerScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  _AccountLedgerQuery get _query => _AccountLedgerQuery(
    accountId: widget.accountId,
    fromDate: _fromDate != null ? _toApiDate(_fromDate!) : null,
    toDate: _toDate != null ? _toApiDate(_toDate!) : null,
    page: _page,
  );

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _toApiDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _dateSubtitle {
    if (_fromDate == null && _toDate == null) return 'All transactions.';
    final f = _fromDate != null ? _fmtDate(_fromDate!) : '…';
    final t = _toDate != null ? _fmtDate(_toDate!) : '…';
    return '$f – $t';
  }

  // ---------------------------------------------------------------------------
  // Date helpers
  // ---------------------------------------------------------------------------

  String _fmtEntryDate(String raw) {
    // If the backend sends YYYY-MM-DD, reformat to DD/MM/YYYY.
    if (raw.length == 10 && raw[4] == '-') {
      return '${raw.substring(8, 10)}/${raw.substring(5, 7)}/${raw.substring(0, 4)}';
    }
    return raw;
  }

  String _voucherLabel(String type) {
    // Return a short human-friendly label for known voucher types.
    switch (type.toUpperCase()) {
      case 'JV':
        return 'Journal';
      case 'PV':
        return 'Payment';
      case 'RV':
        return 'Receipt';
      case 'SV':
        return 'Sales';
      case 'PVT':
        return 'Purchase';
      case 'CN':
        return 'Credit Note';
      case 'DN':
        return 'Debit Note';
      case 'CR':
        return 'Contra';
      default:
        return type.isNotEmpty ? type : '—';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final asyncVal = ref.watch(accountLedgerReportProvider(query));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final displayTitle = widget.accountName.isNotEmpty
        ? widget.accountName
        : 'Account Ledger';
    final subtitle = widget.accountCode.isNotEmpty
        ? '${widget.accountCode}  ·  $_dateSubtitle'
        : _dateSubtitle;

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: displayTitle,
            subtitle: subtitle,
            actions: [_buildDateFilter(colors)],
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 6),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () =>
                    ref.invalidate(accountLedgerReportProvider(query)),
              ),
              data: (report) => _buildContent(report, colors, fmt),
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
      } else {
        _toDate = picked;
      }
      // Reset to first page when the date range changes.
      _page = 1;
    });
  }

  // -------------------------------------------------------------------------
  // Content body
  // -------------------------------------------------------------------------

  Widget _buildContent(
    LedgerReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final lines = report.lines;
    final totalPages = _pageLimit > 0
        ? (report.totalLines + _pageLimit - 1) ~/ _pageLimit
        : 1;
    final hasMore = _page * _pageLimit < report.totalLines;
    final hasPrevious = _page > 1;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        ApexSpacing.sm,
        isMobile ? ApexSpacing.md : ApexSpacing.xl,
        isMobile ? ApexSpacing.lg : ApexSpacing.xl,
      ),
      child: Column(
        children: [
          // Opening balance card
          ApexCard(
            child: Row(
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: ApexSpacing.sm),
                Text(
                  'Opening Balance',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                MonetaryText(
                  value: fmt.currency(report.openingBalance),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ],
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          // Transaction rows — use ApexCard with a column header & rows.
          _buildLinesCard(lines, report, colors, fmt),
          const SizedBox(height: ApexSpacing.md),
          // Closing balance card
          ApexCard(
            child: Row(
              children: [
                Icon(Icons.stop_rounded, size: 18, color: colors.textSecondary),
                const SizedBox(width: ApexSpacing.sm),
                Text(
                  'Closing Balance',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                MonetaryText(
                  value: fmt.currency(report.closingBalance),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ],
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          // Pagination controls
          _buildPagination(totalPages, hasMore, hasPrevious, colors),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Transaction lines table
  // -------------------------------------------------------------------------

  Widget _buildLinesCard(
    List<LedgerLine> lines,
    LedgerReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    if (ResponsiveLayout.isMobile(context)) {
      return _buildMobileLinesCard(lines, report, colors, fmt);
    }

    return ApexCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column headers
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
                  flex: 28,
                  child: Text('PARTICULARS', style: _th(colors)),
                ),
                Expanded(flex: 14, child: Text('TYPE', style: _th(colors))),
                Expanded(
                  flex: 14,
                  child: Text(
                    'DEBIT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 14,
                  child: Text(
                    'CREDIT',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    'BALANCE',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          // Lines
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(ApexSpacing.xl),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions',
                subtitle: 'No entries found for this period.',
              ),
            )
          else
            ...lines.map((l) => _lineRow(l, colors, fmt)),
          // Line count summary
          if (lines.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
                color: colors.surfaceMuted,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ApexSpacing.lg,
                vertical: ApexSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_rounded,
                    size: 14,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${report.totalLines} total entries',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (report.totalLines > _pageLimit) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(page $_page)',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileLinesCard(
    List<LedgerLine> lines,
    LedgerReport report,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ApexSpacing.md,
              vertical: ApexSpacing.md,
            ),
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, size: 18, color: colors.info),
                const SizedBox(width: ApexSpacing.sm),
                Text(
                  'Transactions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(ApexSpacing.xl),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions',
                subtitle: 'No entries found for this period.',
              ),
            )
          else
            ...lines.map((line) => _mobileLineTile(line, colors, fmt)),
          if (lines.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
                color: colors.surfaceMuted,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ApexSpacing.md,
                vertical: ApexSpacing.sm,
              ),
              child: Wrap(
                spacing: ApexSpacing.xs,
                runSpacing: ApexSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_rounded,
                    size: 14,
                    color: colors.textMuted,
                  ),
                  Text(
                    '${report.totalLines} total entries',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (report.totalLines > _pageLimit)
                    Text(
                      '(page $_page)',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _mobileLineTile(
    LedgerLine line,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final hasDebit = line.debitAmount > 0;
    final hasCredit = line.creditAmount > 0;
    final title = line.description.isNotEmpty
        ? line.description
        : line.referenceNumber.isNotEmpty
        ? line.referenceNumber
        : '—';

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(ApexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (line.referenceNumber.isNotEmpty &&
                        title != line.referenceNumber) ...[
                      const SizedBox(height: ApexSpacing.xs),
                      Text(
                        line.referenceNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: ApexSpacing.sm),
              _voucherBadge(line.voucherType, colors),
            ],
          ),
          const SizedBox(height: ApexSpacing.md),
          Row(
            children: [
              Icon(Icons.event_rounded, size: 14, color: colors.textSecondary),
              const SizedBox(width: ApexSpacing.xs),
              Text(
                _fmtEntryDate(line.entryDate),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: ApexSpacing.md),
          _mobileAmountRow(
            'Debit',
            hasDebit ? fmt.currency(line.debitAmount) : '—',
            colors,
          ),
          const SizedBox(height: ApexSpacing.xs),
          _mobileAmountRow(
            'Credit',
            hasCredit ? fmt.currency(line.creditAmount) : '—',
            colors,
          ),
          const Divider(height: ApexSpacing.lg),
          _mobileAmountRow(
            'Running balance',
            fmt.currency(line.runningBalance),
            colors,
            strong: true,
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

  Widget _lineRow(LedgerLine l, ApexColors colors, NumberFormatter fmt) {
    final hasDebit = l.debitAmount > 0;
    final hasCredit = l.creditAmount > 0;
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
          // Date
          Expanded(
            flex: 14,
            child: Text(
              _fmtEntryDate(l.entryDate),
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Particular / description
          Expanded(
            flex: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.description.isNotEmpty
                      ? l.description
                      : l.referenceNumber.isNotEmpty
                      ? l.referenceNumber
                      : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                if (l.description.isNotEmpty && l.referenceNumber.isNotEmpty)
                  Text(
                    l.referenceNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          // Voucher type
          Expanded(flex: 14, child: _voucherBadge(l.voucherType, colors)),
          // Debit
          Expanded(
            flex: 14,
            child: hasDebit
                ? MonetaryText(
                    value: fmt.currency(l.debitAmount),
                    fontSize: 12.5,
                    textAlign: TextAlign.right,
                  )
                : Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
          ),
          // Credit
          Expanded(
            flex: 14,
            child: hasCredit
                ? MonetaryText(
                    value: fmt.currency(l.creditAmount),
                    fontSize: 12.5,
                    textAlign: TextAlign.right,
                  )
                : Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
          ),
          // Running balance
          Expanded(
            flex: 16,
            child: MonetaryText(
              value: fmt.currency(l.runningBalance),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _voucherBadge(String type, ApexColors colors) {
    final label = _voucherLabel(type);
    if (label == '—') {
      return Text('—', style: TextStyle(fontSize: 12, color: colors.textMuted));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ApexRadius_sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Pagination
  // -------------------------------------------------------------------------

  Widget _buildPagination(
    int totalPages,
    bool hasMore,
    bool hasPrevious,
    ApexColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ApexSpacing.md,
        vertical: ApexSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius_lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous button
          _pageButton(
            icon: Icons.chevron_left_rounded,
            label: 'Previous',
            enabled: hasPrevious,
            onTap: () => setState(() => _page--),
            colors: colors,
          ),
          // Page indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ApexSpacing.md),
            child: Text(
              'Page $_page of $totalPages',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          // Next button
          _pageButton(
            icon: Icons.chevron_right_rounded,
            label: 'Next',
            enabled: hasMore,
            onTap: () => setState(() => _page++),
            colors: colors,
            isNext: true,
          ),
        ],
      ),
    );
  }

  Widget _pageButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    required ApexColors colors,
    bool isNext = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ApexRadius_md),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ApexSpacing.sm,
            vertical: ApexSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isNext)
                Icon(icon, size: 18, color: _btnColor(enabled, colors)),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _btnColor(enabled, colors),
                ),
              ),
              if (isNext)
                Icon(icon, size: 18, color: _btnColor(enabled, colors)),
            ],
          ),
        ),
      ),
    );
  }

  Color _btnColor(bool enabled, ApexColors colors) =>
      enabled ? colors.primary : colors.textMuted;

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}
