import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/tables/table_pagination.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import '../models/invoice.dart';
import 'invoice_list_provider.dart';
import 'invoice_detail_screen.dart';
import 'invoice_form_screen.dart';
import 'invoice_search_bar.dart';
import 'invoice_table_body.dart';

/// Lightweight table controller for the invoice list screen.
final _invoiceTableCtrlProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>(
      (ref) => ApexTableController(),
    );

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});
  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  InvoiceListItem? _selectedItem;
  late final ApexTableController _tableCtrl;
  InvoiceListQuery _query = const InvoiceListQuery(page: 1, limit: 25);

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(_invoiceTableCtrlProvider);
    _tableCtrl.addListener(_onTableChange);
  }

  @override
  void dispose() {
    _tableCtrl.removeListener(_onTableChange);
    super.dispose();
  }

  InvoiceListQuery _buildQuery() {
    final s = _tableCtrl.value;
    return InvoiceListQuery(
      page: s.page,
      limit: s.limit,
      search: s.search.trim().isEmpty ? null : s.search.trim(),
      status: s.statusFilter,
    );
  }

  void _onTableChange() {
    setState(() => _query = _buildQuery());
  }

  @override
  Widget build(BuildContext context) {
    final asyncPaged = ref.watch(invoiceListProvider(_query));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Sales Invoices',
            subtitle: 'Billing and collections.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Invoice'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const InvoiceFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(invoiceListProvider)),
              ),
            ],
          ),
          // Search + status filters
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
                      InvoiceSearchBar(controller: _tableCtrl),
                      const SizedBox(height: 8),
                      _StatusFilterBar(controller: _tableCtrl),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: InvoiceSearchBar(controller: _tableCtrl)),
                      const SizedBox(width: 16),
                      _StatusFilterBar(controller: _tableCtrl),
                    ],
                  ),
          ),
          // Table body + pagination
          Expanded(
            child: asyncPaged.when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(invoiceListProvider),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  final filtering =
                      _query.search != null || _query.status != null;
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: filtering
                        ? 'No matching invoices'
                        : 'No invoices yet',
                    subtitle: filtering
                        ? 'Try clearing filters or searching a different term.'
                        : 'Create your first invoice to start billing.',
                    actionLabel: filtering ? null : 'New Invoice',
                    onAction: filtering
                        ? null
                        : () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const InvoiceFormScreen(),
                                ),
                              )
                              .then((_) => ref.invalidate(invoiceListProvider)),
                  );
                }
                final paged = Paged<InvoiceListItem>(
                  items: data.items,
                  total: data.total,
                  page: _query.page,
                  limit: _query.limit,
                );
                return Column(
                  children: [
                    Expanded(
                      child: InvoiceTableBody(
                        items: data.items,
                        sort: _tableCtrl.value.sort,
                        onSort: (id) => _tableCtrl.toggleSort(id),
                        selectedId: _selectedItem?.id,
                        onSelect: (item) =>
                            setState(() => _selectedItem = item),
                        fmt: fmt,
                        colors: colors,
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

    if (_selectedItem == null) {
      return list;
    }

    if (ResponsiveLayout.isMobile(context)) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selectedItem = null);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _selectedItem!.invoiceNumber,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _selectedItem = null),
            ),
          ),
          body: InvoiceDetailScreen(invoiceId: _selectedItem!.id),
        ),
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: list),
        const VerticalDivider(width: 1),
        Container(
          width: 380,
          color: colors.surfaceMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBar(
                title: Text(
                  _selectedItem!.invoiceNumber,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selectedItem = null),
                ),
              ),
              Expanded(
                child: InvoiceDetailScreen(invoiceId: _selectedItem!.id),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Segmented status filter — one click narrows the grid by lifecycle state.
class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.controller});
  final ApexTableController controller;

  static const _options = [
    ('All', null),
    ('Draft', 'DRAFT'),
    ('Posted', 'POSTED'),
    ('Sent', 'SENT'),
    ('Partial', 'PARTIALLY_PAID'),
    ('Paid', 'PAID'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final active = state.statusFilter;
        return Container(
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
                    color: selected ? colors.surfaceRaised : Colors.transparent,
                    borderRadius: BorderRadius.circular(ApexRadius.sm),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
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
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
