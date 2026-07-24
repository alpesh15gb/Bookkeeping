/// Vendor Ledger screen — party statement for a selected vendor.
///
/// Shows all transactions (bills, payments, returns, etc.) for a vendor
/// within a date range with running balance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/report_models.dart';
import '../services/reports_service.dart';

// ---------------------------------------------------------------------------
// Riverpod state
// ---------------------------------------------------------------------------

final vlDateFromProvider = StateProvider<String?>((ref) => null);
final vlDateToProvider = StateProvider<String?>((ref) => null);
final vlContactIdProvider = StateProvider<String?>((ref) => null);

final vendorLedgerProvider =
    FutureProvider.autoDispose<PartyStatement?>((ref) async {
  final contactId = ref.watch(vlContactIdProvider);
  final dateFrom = ref.watch(vlDateFromProvider);
  final dateTo = ref.watch(vlDateToProvider);
  if (contactId == null || dateFrom == null || dateTo == null) return null;
  final res = await ref
      .watch(reportsServiceProvider)
      .getPartyStatement(
        contactId: contactId,
        startDate: dateFrom,
        endDate: dateTo,
      );
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

// ---------------------------------------------------------------------------
// Vendor Search Delegate
// ---------------------------------------------------------------------------

class VendorLedgerSearchDelegate extends SearchDelegate<ContactSummary?> {
  VendorLedgerSearchDelegate(this.reportsService, this.colors) : super();
  final ReportsService reportsService;
  final ApexColors colors;

  @override
  String? get searchFieldLabel => 'Search vendor…';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: Theme.of(context).appBarTheme.copyWith(
            backgroundColor: colors.surface,
          ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    if (query.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(ApexSpacing.xxl),
          child: Text('Type at least 2 characters to search.'),
        ),
      );
    }

    return FutureBuilder<Result<List<ContactSummary>>>(
      future: reportsService
          .getContacts(contactType: 'VENDOR', search: query),
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (result is! Success<List<ContactSummary>>) {
          return const Center(child: Text('Search failed.'));
        }
        final contacts = result.value;
        if (contacts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(ApexSpacing.xxl),
              child: Text('No vendors found.'),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: ApexSpacing.sm),
          itemCount: contacts.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: colors.border),
          itemBuilder: (context, i) {
            final c = contacts[i];
            return ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ),
              title: Text(c.name),
              onTap: () => close(context, c),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class VendorLedgerScreen extends ConsumerStatefulWidget {
  const VendorLedgerScreen({super.key});
  @override
  ConsumerState<VendorLedgerScreen> createState() =>
      _VendorLedgerScreenState();
}

class _VendorLedgerScreenState extends ConsumerState<VendorLedgerScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  ContactSummary? _selectedVendor;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    Future.microtask(() {
      ref.read(vlDateFromProvider.notifier).state = _toApiDate(_fromDate!);
      ref.read(vlDateToProvider.notifier).state = _toApiDate(_toDate!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(vendorLedgerProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Vendor Ledger',
            subtitle: 'Transaction history for a selected vendor.',
            actions: [_buildDateFilter(colors)],
          ),
          // Vendor selector
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ApexSpacing.xl,
              0,
              ApexSpacing.xl,
              ApexSpacing.sm,
            ),
            child: _buildVendorSelector(colors),
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
                onRetry: () => ref.invalidate(vendorLedgerProvider),
              ),
              data: (statement) {
                if (statement == null) {
                  return const EmptyState(
                    icon: Icons.person_search_rounded,
                    title: 'Select a vendor',
                    subtitle:
                        'Search and select a vendor to view their ledger.',
                  );
                }
                if (statement.ledger.isEmpty) {
                  return const EmptyState(
                    icon: Icons.assignment_rounded,
                    title: 'No transactions',
                    subtitle:
                        'No entries for this vendor in the selected period.',
                  );
                }
                return _buildStatement(statement, colors, fmt);
              },
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Vendor selector
  // -----------------------------------------------------------------------

  Widget _buildVendorSelector(ApexColors colors) {
    return InkWell(
      onTap: () async {
        final result = await showSearch<ContactSummary?>(
          context: context,
          delegate: VendorLedgerSearchDelegate(ref.read(reportsServiceProvider), colors),
        );
        if (result != null) {
          setState(() => _selectedVendor = result);
          ref.read(vlContactIdProvider.notifier).state = result.id;
        }
      },
      borderRadius: BorderRadius.circular(ApexRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.business_rounded,
              size: 16,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedVendor?.name ?? 'Select a vendor…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _selectedVendor != null
                      ? colors.textPrimary
                      : colors.textMuted,
                ),
              ),
            ),
            if (_selectedVendor != null)
              GestureDetector(
                onTap: () {
                  setState(() => _selectedVendor = null);
                  ref.read(vlContactIdProvider.notifier).state = null;
                },
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colors.textMuted,
                ),
              )
            else
              Icon(
                Icons.search_rounded,
                size: 16,
                color: colors.textMuted,
              ),
          ],
        ),
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
        ref.read(vlDateFromProvider.notifier).state = _toApiDate(picked);
      } else {
        _toDate = picked;
        ref.read(vlDateToProvider.notifier).state = _toApiDate(picked);
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
    } catch (e) {
      debugPrint('VendorLedgerScreen: failed to format date — $e');
    }
    return isoDate;
  }

  // -----------------------------------------------------------------------
  // Statement body
  // -----------------------------------------------------------------------

  Widget _buildStatement(
    PartyStatement statement,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ApexSpacing.xl,
        0,
        ApexSpacing.xl,
        ApexSpacing.xl,
      ),
      child: Column(
        children: [
          // Contact info card
          _buildContactInfo(statement, colors),
          const SizedBox(height: ApexSpacing.md),

          // Ledger table
          _buildLedgerTable(statement, colors, fmt),
          const SizedBox(height: ApexSpacing.md),

          // Summary card
          _buildSummary(statement.summary, colors, fmt),
        ],
      ),
    );
  }

  Widget _buildContactInfo(PartyStatement statement, ApexColors colors) {
    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statement.contactName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          if (statement.gstin != null && statement.gstin!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'GSTIN: ${statement.gstin}',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Period: ${_fmtDateShort(statement.startDate)} — ${_fmtDateShort(statement.endDate)}',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerTable(
    PartyStatement statement,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      padding: EdgeInsets.zero,
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
              children: [
                Expanded(flex: 16, child: Text('DATE', style: _th(colors))),
                Expanded(
                  flex: 16,
                  child: Text('VOUCHER #', style: _th(colors)),
                ),
                Expanded(
                  flex: 16,
                  child: Text('TYPE', style: _th(colors)),
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
                  flex: 20,
                  child: Text(
                    'BALANCE',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          for (final row in statement.ledger)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ApexSpacing.lg,
                vertical: ApexSpacing.sm,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 16,
                    child: Text(
                      _fmtDateShort(row.date),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 16,
                    child: Text(
                      row.voucherNo,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 16,
                    child: Text(
                      row.voucherType,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 16,
                    child: row.debit != null
                        ? MonetaryText(
                            value: fmt.currency(row.debit!, showSymbol: false),
                            fontSize: 12.5,
                            color: colors.textPrimary,
                            textAlign: TextAlign.right,
                          )
                        : Text(
                            '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textMuted,
                            ),
                          ),
                  ),
                  Expanded(
                    flex: 16,
                    child: row.credit != null
                        ? MonetaryText(
                            value: fmt.currency(row.credit!, showSymbol: false),
                            fontSize: 12.5,
                            color: colors.textPrimary,
                            textAlign: TextAlign.right,
                          )
                        : Text(
                            '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textMuted,
                            ),
                          ),
                  ),
                  Expanded(
                    flex: 20,
                    child: Text(
                      row.balance,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
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

  Widget _buildSummary(
    PartyStatementSummary summary,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: ApexSpacing.sm),
          _summaryRow('Opening Balance', fmt.currency(summary.openingBalance),
              colors),
          _summaryRow(
            'Total Purchases',
            fmt.currency(summary.totalPurchases),
            colors,
          ),
          _summaryRow(
            'Total Payments',
            fmt.currency(summary.totalPayments),
            colors,
          ),
          const Divider(height: ApexSpacing.lg),
          _summaryRow(
            'Closing Outstanding',
            fmt.currency(summary.closingOutstanding),
            colors,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    ApexColors colors, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          MonetaryText(
            value: value,
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: bold ? colors.textPrimary : colors.textPrimary,
            textAlign: TextAlign.right,
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
