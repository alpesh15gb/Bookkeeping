/// Proforma Invoice (Quotation) list screen with paginated list, status filter,
/// and navigation to form/detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/tables/table_pagination.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import 'proforma_form_screen.dart';
import 'proforma_detail_screen.dart';
import 'invoice_search_bar.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

@immutable
class ProformaListItem {
  const ProformaListItem({
    required this.id,
    this.proformaNumber = '',
    this.issueDate = '',
    this.dueDate = '',
    this.status = 'DRAFT',
    this.total = 0,
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String proformaNumber;
  final String issueDate;
  final String dueDate;
  final String status;
  final double total;
  final String contactName;
  final String? createdAt;

  factory ProformaListItem.fromJson(Map<String, dynamic> json) =>
      ProformaListItem(
        id: (json['id'] ?? '').toString(),
        proformaNumber: json['proforma_number'] as String? ?? '',
        issueDate: json['issue_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        status: json['status'] as String? ?? 'DRAFT',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        contactName: json['contact_name'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

class ProformaListQuery {
  const ProformaListQuery({
    this.page = 1,
    this.limit = 25,
    this.status,
    this.search,
  });
  final int page, limit;
  final String? status;
  final String? search;

  ProformaListQuery copyWith({
    int? page,
    int? limit,
    String? status,
    String? search,
  }) => ProformaListQuery(
    page: page ?? this.page,
    limit: limit ?? this.limit,
    status: status ?? this.status,
    search: search ?? this.search,
  );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final proformaListProvider = FutureProvider.autoDispose
    .family<({List<ProformaListItem> items, int total}), ProformaListQuery>((
      ref,
      query,
    ) async {
      final dio = ref.watch(apiClientProvider);
      final q = <String, dynamic>{'page': query.page, 'limit': query.limit};
      final res = await dio.get('/proforma-invoices', queryParameters: q);
      final raw = res.data;
      final rawItems = (raw as List)
          .map((e) => ProformaListItem.fromJson(e as Map<String, dynamic>))
          .toList();
      var items = query.status == null
          ? rawItems
          : rawItems.where((e) => e.status == query.status).toList();
      final search = query.search?.trim().toLowerCase();
      if (search != null && search.isNotEmpty) {
        items = items
            .where(
              (item) =>
                  item.proformaNumber.toLowerCase().contains(search) ||
                  item.contactName.toLowerCase().contains(search),
            )
            .toList();
      }
      final total = rawItems.length < query.limit
          ? (query.page - 1) * query.limit + items.length
          : query.page * query.limit + 1;
      return (items: items, total: total);
    });

final _proformaTableCtrlProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>(
      (ref) => ApexTableController(),
    );

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ProformaListScreen extends ConsumerStatefulWidget {
  const ProformaListScreen({super.key});
  @override
  ConsumerState<ProformaListScreen> createState() => _ProformaListScreenState();
}

class _ProformaListScreenState extends ConsumerState<ProformaListScreen> {
  ProformaListItem? _selectedItem;
  late final ApexTableController _tableCtrl;
  ProformaListQuery _query = const ProformaListQuery(page: 1, limit: 25);

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(_proformaTableCtrlProvider);
    _tableCtrl.addListener(_onTableChange);
  }

  @override
  void dispose() {
    _tableCtrl.removeListener(_onTableChange);
    super.dispose();
  }

  ProformaListQuery _buildQuery() {
    final s = _tableCtrl.value;
    return ProformaListQuery(
      page: s.page,
      limit: s.limit,
      status: s.statusFilter,
      search: s.search.trim().isEmpty ? null : s.search.trim(),
    );
  }

  void _onTableChange() {
    setState(() => _query = _buildQuery());
  }

  @override
  Widget build(BuildContext context) {
    final asyncPaged = ref.watch(proformaListProvider(_query));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Quotations',
            subtitle: 'Proforma invoices and estimates.',
            actions: [
              PermissionGate(
                permission: Permissions.invoiceCreate,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New Quotation'),
                  onPressed: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => const ProformaFormScreen(),
                        ),
                      )
                      .then((_) => ref.invalidate(proformaListProvider)),
                ),
              ),
            ],
          ),
          // Search + status filter
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveLayout.isMobile(context) ? 12 : 24,
              0,
              ResponsiveLayout.isMobile(context) ? 12 : 24,
              8,
            ),
            child: ResponsiveLayout.isMobile(context)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InvoiceSearchBar(
                        controller: _tableCtrl,
                        hintText: 'Search quotations by number or customer…',
                      ),
                      const SizedBox(height: 8),
                      _StatusFilterBar(controller: _tableCtrl),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: InvoiceSearchBar(
                          controller: _tableCtrl,
                          hintText: 'Search quotations by number or customer…',
                        ),
                      ),
                      const SizedBox(width: 16),
                      _StatusFilterBar(controller: _tableCtrl),
                    ],
                  ),
          ),
          // Table body + pagination
          Expanded(
            child: asyncPaged.when(
              loading: () => ShimmerSkeleton(
                child: Column(
                  children: [
                    for (int i = 0; i < 6; i++)
                      const TableRowSkeleton(columns: 5),
                  ],
                ),
              ),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(proformaListProvider),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  final filtering =
                      _query.status != null || _query.search != null;
                  return EmptyState(
                    icon: Icons.description_outlined,
                    title: filtering
                        ? 'No matching quotations'
                        : 'No quotations yet',
                    subtitle: filtering
                        ? 'Try clearing the status filter.'
                        : 'Create a proforma invoice to start quoting.',
                    actionLabel: filtering ? null : 'New Quotation',
                    onAction: filtering
                        ? null
                        : () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const ProformaFormScreen(),
                                ),
                              )
                              .then(
                                (_) => ref.invalidate(proformaListProvider),
                              ),
                  );
                }
                final paged = Paged<ProformaListItem>(
                  items: data.items,
                  total: data.total,
                  page: _query.page,
                  limit: _query.limit,
                );
                return Column(
                  children: [
                    Expanded(
                      child: _TableBody(
                        items: data.items,
                        colors: colors,
                        fmt: fmt,
                        selectedId: _selectedItem?.id,
                        onSelect: (item) =>
                            setState(() => _selectedItem = item),
                      ),
                    ),
                    ApexPaginationControls(
                      controller: _tableCtrl,
                      paged: paged,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );

    Widget content;
    if (_selectedItem == null) {
      content = list;
    } else if (ResponsiveLayout.isMobile(context)) {
      content = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selectedItem = null);
        },
        child: ProformaDetailScreen(
          proformaId: _selectedItem!.id,
          embedded: true,
          onClose: () => setState(() => _selectedItem = null),
        ),
      );
    } else {
      content = Row(
        children: [
          Expanded(flex: 3, child: list),
          const VerticalDivider(width: 1),
          SizedBox(
            width: MediaQuery.sizeOf(context).width >= 1440 ? 560 : 460,
            child: ProformaDetailScreen(
              proformaId: _selectedItem!.id,
              embedded: true,
              onClose: () => setState(() => _selectedItem = null),
            ),
          ),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            Navigator.of(context)
                .push(
                  MaterialPageRoute(builder: (_) => const ProformaFormScreen()),
                )
                .then((_) => ref.invalidate(proformaListProvider)),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedItem != null) setState(() => _selectedItem = null);
        },
      },
      child: Focus(autofocus: true, child: content),
    );
  }
}

// ---------------------------------------------------------------------------
// Table body
// ---------------------------------------------------------------------------

class _TableBody extends StatelessWidget {
  const _TableBody({
    required this.items,
    required this.colors,
    required this.fmt,
    required this.selectedId,
    required this.onSelect,
  });

  final List<ProformaListItem> items;
  final ApexColors colors;
  final NumberFormatter fmt;
  final String? selectedId;
  final void Function(ProformaListItem) onSelect;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 600) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            margin: EdgeInsets.zero,
            color: item.id == selectedId ? colors.primaryContainer : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(ApexRadius.lg),
              onTap: () => onSelect(item),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.proformaNumber,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        MonetaryText(
                          value: fmt.currency(item.total),
                          fontWeight: FontWeight.w800,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.contactName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusBadge(
                          label: item.status,
                          tone: toneForStatus(item.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Valid until ${item.dueDate}',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 800,
        child: Column(
          children: [
            // Header
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _header('PROFORMA #', 140, colors),
                  _header('Customer', 180, colors),
                  _header('Issued', 100, colors),
                  _header('Due', 100, colors),
                  _header('Total', 120, colors, alignRight: true),
                  _header('Status', 120, colors),
                ],
              ),
            ),
            // Rows
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return InkWell(
                    onTap: () => onSelect(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              item.proformaNumber,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: Text(
                              item.contactName,
                              style: textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              item.issueDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              item.dueDate,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: MonetaryText(
                              value: fmt.currency(item.total),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: StatusBadge(
                              label: item.status,
                              tone: toneForStatus(item.status),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    String label,
    double width,
    ApexColors colors, {
    bool alignRight = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status filter bar
// ---------------------------------------------------------------------------

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.controller});
  final ApexTableController controller;

  static const _options = [
    ('All', null),
    ('Draft', 'DRAFT'),
    ('Issued', 'ISSUED'),
    ('Converted', 'CONVERTED'),
    ('Cancelled', 'CANCELLED'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final active = state.statusFilter;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(ApexRadius.md),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _options.map((o) {
                final selected = active == o.$2;
                return GestureDetector(
                  onTap: () => controller.setStatusFilter(o.$2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.surfaceRaised
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(ApexRadius.sm),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      o.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
