/// Sales Order list screen with status filter (Draft/Confirmed/Delivered/Cancelled).
library;

import 'package:flutter/material.dart';
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
import 'sales_order_form_screen.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

@immutable
class SalesOrderListItem {
  const SalesOrderListItem({
    required this.id,
    this.soNumber = '',
    this.orderDate = '',
    this.dueDate = '',
    this.status = 'DRAFT',
    this.total = 0,
    this.amountAdvanced = 0,
    this.contactName = '',
    this.createdAt,
  });

  final String id;
  final String soNumber;
  final String orderDate;
  final String dueDate;
  final String status;
  final double total;
  final double amountAdvanced;
  final String contactName;
  final String? createdAt;

  factory SalesOrderListItem.fromJson(Map<String, dynamic> json) =>
      SalesOrderListItem(
        id: (json['id'] ?? '').toString(),
        soNumber: json['so_number'] as String? ?? '',
        orderDate: json['order_date'] as String? ?? '',
        dueDate: json['due_date'] as String? ?? '',
        status: json['status'] as String? ?? 'DRAFT',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        amountAdvanced: (json['amount_advanced'] as num?)?.toDouble() ?? 0,
        contactName: json['contact_name'] as String? ?? '',
        createdAt: json['created_at'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

class SalesOrderListQuery {
  const SalesOrderListQuery({this.page = 1, this.limit = 25, this.status});
  final int page, limit;
  final String? status;

  SalesOrderListQuery copyWith({int? page, int? limit, String? status}) =>
      SalesOrderListQuery(
        page: page ?? this.page,
        limit: limit ?? this.limit,
        status: status ?? this.status,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final salesOrderListProvider = FutureProvider.autoDispose
    .family<({List<SalesOrderListItem> items, int total}), SalesOrderListQuery>(
      (ref, query) async {
        final dio = ref.watch(apiClientProvider);
        final q = <String, dynamic>{'page': query.page, 'limit': query.limit};
        final res = await dio.get('/sales-orders', queryParameters: q);
        final raw = res.data;
        final rawItems = (raw as List)
            .map((e) => SalesOrderListItem.fromJson(e as Map<String, dynamic>))
            .toList();
        final items = query.status == null
            ? rawItems
            : rawItems.where((e) => e.status == query.status).toList();
        final total = rawItems.length < query.limit
            ? (query.page - 1) * query.limit + items.length
            : query.page * query.limit + 1;
        return (items: items, total: total);
      },
    );

final _soTableCtrlProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>(
      (ref) => ApexTableController(),
    );

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SalesOrderListScreen extends ConsumerStatefulWidget {
  const SalesOrderListScreen({super.key});
  @override
  ConsumerState<SalesOrderListScreen> createState() =>
      _SalesOrderListScreenState();
}

class _SalesOrderListScreenState extends ConsumerState<SalesOrderListScreen> {
  late final ApexTableController _tableCtrl;
  SalesOrderListQuery _query = const SalesOrderListQuery(page: 1, limit: 25);

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(_soTableCtrlProvider);
    _tableCtrl.addListener(_onTableChange);
  }

  @override
  void dispose() {
    _tableCtrl.removeListener(_onTableChange);
    super.dispose();
  }

  SalesOrderListQuery _buildQuery() {
    final s = _tableCtrl.value;
    return SalesOrderListQuery(
      page: s.page,
      limit: s.limit,
      status: s.statusFilter,
    );
  }

  void _onTableChange() {
    setState(() => _query = _buildQuery());
  }

  Future<void> _workflowAction(SalesOrderListItem item, String action) async {
    try {
      final suffix = action == 'confirm'
          ? 'confirm'
          : 'create-delivery-challan';
      await ref
          .read(apiClientProvider)
          .post('/sales-orders/${item.id}/$suffix');
      ref.invalidate(salesOrderListProvider);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'confirm'
                  ? 'Sales order confirmed.'
                  : 'Delivery challan created.',
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Action failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncPaged = ref.watch(salesOrderListProvider(_query));
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    final list = Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Sales Orders',
            subtitle: 'Customer orders and fulfilment.',
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New Order'),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const SalesOrderFormScreen(),
                      ),
                    )
                    .then((_) => ref.invalidate(salesOrderListProvider)),
              ),
            ],
          ),
          // Status filter
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveLayout.isMobile(context) ? 12 : 24,
              0,
              ResponsiveLayout.isMobile(context) ? 12 : 24,
              8,
            ),
            child: _StatusFilterBar(controller: _tableCtrl),
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
                onRetry: () => ref.invalidate(salesOrderListProvider),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  final filtering = _query.status != null;
                  return EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: filtering
                        ? 'No matching orders'
                        : 'No sales orders yet',
                    subtitle: filtering
                        ? 'Try clearing the status filter.'
                        : 'Create a sales order to track customer commitments.',
                    actionLabel: filtering ? null : 'New Order',
                    onAction: filtering
                        ? null
                        : () => Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (_) => const SalesOrderFormScreen(),
                                ),
                              )
                              .then(
                                (_) => ref.invalidate(salesOrderListProvider),
                              ),
                  );
                }
                final paged = Paged<SalesOrderListItem>(
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
                        onWorkflow: _workflowAction,
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

    return list;
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
    required this.onWorkflow,
  });

  final List<SalesOrderListItem> items;
  final ApexColors colors;
  final NumberFormatter fmt;
  final void Function(SalesOrderListItem, String) onWorkflow;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 860,
        child: Column(
          children: [
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _header('ORDER #', 140, colors),
                  _header('Customer', 180, colors),
                  _header('Order Date', 100, colors),
                  _header('Due Date', 100, colors),
                  _header('Total', 120, colors, alignRight: true),
                  _header('Advance', 100, colors, alignRight: true),
                  _header('Status', 120, colors),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SalesOrderFormScreen(editId: item.id),
                        ),
                      );
                    },
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
                              item.soNumber,
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
                              item.orderDate,
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
                            width: 100,
                            child: MonetaryText(
                              value: fmt.currency(item.amountAdvanced),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              textAlign: TextAlign.right,
                              color: item.amountAdvanced > 0
                                  ? colors.success
                                  : null,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: StatusBadge(
                              label: item.status,
                              tone: toneForStatus(item.status),
                            ),
                          ),
                          if (item.status == 'DRAFT' ||
                              item.status == 'CONFIRMED')
                            PopupMenuButton<String>(
                              tooltip: 'Workflow actions',
                              onSelected: (value) => onWorkflow(item, value),
                              itemBuilder: (_) => [
                                if (item.status == 'DRAFT')
                                  const PopupMenuItem(
                                    value: 'confirm',
                                    child: Text('Confirm order'),
                                  ),
                                if (item.status == 'CONFIRMED')
                                  const PopupMenuItem(
                                    value: 'dispatch',
                                    child: Text('Create delivery challan'),
                                  ),
                              ],
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
    ('Confirmed', 'CONFIRMED'),
    ('Delivered', 'DELIVERED'),
    ('Cancelled', 'CANCELLED'),
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
