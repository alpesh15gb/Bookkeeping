/// Purchase Register screen — list of vendor bills in a date range.
///
/// Mirrors the SalesRegisterScreen pattern with columns for Bill# and Vendor.
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
// Riverpod state
// ---------------------------------------------------------------------------

final prDateFromProvider = StateProvider<String?>((ref) => null);
final prDateToProvider = StateProvider<String?>((ref) => null);
final prContactIdProvider = StateProvider<String?>((ref) => null);

final purchaseRegisterProvider =
    FutureProvider.autoDispose<List<PurchaseTransaction>>((ref) async {
  final dateFrom = ref.watch(prDateFromProvider);
  final dateTo = ref.watch(prDateToProvider);
  final contactId = ref.watch(prContactIdProvider);
  final res = await ref.watch(reportsServiceProvider).getBills(
        dateFrom: dateFrom,
        dateTo: dateTo,
        contactId: contactId,
      );
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

// ---------------------------------------------------------------------------
// Vendor search delegate — pops with the selected contact id & name
// ---------------------------------------------------------------------------

class VendorSearchDelegate extends SearchDelegate<ContactSummary?> {
  VendorSearchDelegate(this.reportsService, this.colors) : super();
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

class PurchaseRegisterScreen extends ConsumerStatefulWidget {
  const PurchaseRegisterScreen({super.key});
  @override
  ConsumerState<PurchaseRegisterScreen> createState() =>
      _PurchaseRegisterScreenState();
}

class _PurchaseRegisterScreenState
    extends ConsumerState<PurchaseRegisterScreen> {
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
      ref.read(prDateFromProvider.notifier).state = _toApiDate(_fromDate!);
      ref.read(prDateToProvider.notifier).state = _toApiDate(_toDate!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncVal = ref.watch(purchaseRegisterProvider);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Purchase Register',
            subtitle: 'All vendor bills for the selected period.',
            actions: [_buildDateFilter(colors)],
          ),
          // Vendor filter
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ApexSpacing.xl,
              0,
              ApexSpacing.xl,
              ApexSpacing.sm,
            ),
            child: _buildVendorFilter(colors),
          ),
          Expanded(
            child: asyncVal.when(
              loading: () => const ShimmerSkeleton(
                child: Padding(
                  padding: EdgeInsets.all(ApexSpacing.xl),
                  child: Column(
                    children: [
                      TableRowSkeleton(columns: 4),
                      TableRowSkeleton(columns: 4),
                      TableRowSkeleton(columns: 4),
                      TableRowSkeleton(columns: 4),
                      TableRowSkeleton(columns: 4),
                    ],
                  ),
                ),
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(purchaseRegisterProvider),
              ),
              data: (bills) {
                if (bills.isEmpty) {
                  return const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'No purchases for this period',
                    subtitle: 'Try adjusting the date range or vendor filter.',
                  );
                }
                return _buildTable(bills, colors, fmt);
              },
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Vendor filter
  // -----------------------------------------------------------------------

  Widget _buildVendorFilter(ApexColors colors) {
    return InkWell(
      onTap: () async {
        final result = await showSearch<ContactSummary?>(
          context: context,
          delegate: VendorSearchDelegate(ref.read(reportsServiceProvider), colors),
        );
        if (result != null) {
          setState(() => _selectedVendor = result);
          ref.read(prContactIdProvider.notifier).state = result.id;
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
                _selectedVendor?.name ?? 'All vendors',
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
                  ref.read(prContactIdProvider.notifier).state = null;
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
        ref.read(prDateFromProvider.notifier).state = _toApiDate(picked);
      } else {
        _toDate = picked;
        ref.read(prDateToProvider.notifier).state = _toApiDate(picked);
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
      debugPrint('PurchaseRegisterScreen: failed to format date — $e');
    }
    return isoDate;
  }

  // -----------------------------------------------------------------------
  // Data table
  // -----------------------------------------------------------------------

  Widget _buildTable(
    List<PurchaseTransaction> bills,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final totalCount = bills.length;
    final totalAmount = bills.fold<double>(0, (s, b) => s + b.total);

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
                Expanded(flex: 16, child: Text('DATE', style: _th(colors))),
                Expanded(
                  flex: 20,
                  child: Text('BILL #', style: _th(colors)),
                ),
                Expanded(
                  flex: 32,
                  child: Text('VENDOR', style: _th(colors)),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    'TOTAL',
                    textAlign: TextAlign.right,
                    style: _th(colors),
                  ),
                ),
                Expanded(
                  flex: 16,
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
              itemCount: bills.length,
              itemBuilder: (context, i) {
                final b = bills[i];
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
                        flex: 16,
                        child: Text(
                          _fmtDateShort(b.issueDate),
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 20,
                        child: Text(
                          b.billNumber,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 32,
                        child: Text(
                          b.vendorName,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 16,
                        child: MonetaryText(
                          value: fmt.currency(b.total),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 16,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: StatusBadge(
                            label: b.status.replaceAll('_', ' '),
                            tone: toneForStatus(b.status),
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
                  flex: 68,
                  child: Text(
                    'TOTAL  ·  $totalCount bill${totalCount == 1 ? '' : 's'}',
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
                    value: fmt.currency(totalAmount),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    textAlign: TextAlign.right,
                  ),
                ),
                const Expanded(flex: 16, child: SizedBox()),
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
