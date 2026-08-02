/// Sales Order list screen with status filter (Draft/Confirmed/Delivered/Cancelled).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:apexbooks/core/database/database_provider.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/widgets/monetary_text.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/tables/table_pagination.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/features/offline_repository_providers.dart';
import 'package:apexbooks/features/sales/domain/commands/sales_commands.dart';
import 'package:apexbooks/core/errors/user_message.dart';
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

final salesOrderListProvider = StreamProvider.autoDispose
    .family<({List<SalesOrderListItem> items, int total}), SalesOrderListQuery>(
      (ref, query) {
        final repo = ref.watch(salesRepositoryProvider);
        return repo.watchSalesOrders().map((list) {
          final rawItems = list.map((item) {
            return SalesOrderListItem(
              id: item.localId,
              soNumber: item.localId.substring(0, 8).toUpperCase(),
              orderDate: item.orderDate,
              dueDate: item.orderDate,
              status: item.status,
              total: item.totalPaise / 100.0,
              contactName: item.customerName,
              createdAt: item.createdAt.toIso8601String(),
            );
          }).toList();
          final items = query.status == null
              ? rawItems
              : rawItems.where((e) => e.status == query.status).toList();
          return (items: items, total: items.length);
        });
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
    if (action == 'print') {
      final result = await ref
          .read(downloadServiceProvider)
          .download(
            relativeUrl: '/sales-orders/${item.id}/print',
            filename: 'Sales_Order_${item.soNumber}',
            kind: ExportKind.pdf,
          );
      if (!mounted) return;
      final message = switch (result) {
        Success() => 'Sales order PDF saved.',
        Failure(:final error) => 'Unable to create PDF: ${error.message}',
        _ => 'Unable to create PDF.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    try {
      if (action == 'confirm') {
        final db = ref.read(databaseProvider);
        await (db.update(db.salesOrders)
              ..where((o) => o.localId.equals(item.id)))
            .write(SalesOrdersCompanion(
              status: const Value('CONFIRMED'),
              updatedAt: Value(DateTime.now().toUtc()),
            ));
      } else {
        final repo = ref.read(salesRepositoryProvider);
        final so = await repo.getSalesOrder(item.id);
        if (so != null) {
          await repo.deliverGoods(
            DeliverGoodsCommand(
              companyId: so.companyId,
              salesOrderLocalId: so.localId,
              deliveryDate: DateTime.now().toUtc().toIso8601String().split('T').first,
              customerId: so.customerId,
              customerName: so.customerName,
              lines: so.lines.map((l) {
                final ordered = double.tryParse(l.quantityOrdered) ?? 0;
                final delivered = double.tryParse(l.quantityDelivered) ?? 0;
                final remaining = (ordered - delivered).clamp(0.0, double.infinity);
                return SalesDeliveryLineCommand(
                  salesOrderLineLocalId: l.localId,
                  productName: l.productName,
                  unit: l.unit,
                  quantityDelivered: remaining.toStringAsFixed(3),
                  unitPricePaise: l.unitPricePaise,
                  sortOrder: l.sortOrder,
                );
              }).toList(),
            ),
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'confirm'
                  ? 'Sales order confirmed.'
                  : 'Delivery challan created.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(error))));
      }
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
                message: userFacingErrorMessage(err),
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
    if (ResponsiveLayout.isMobile(context)) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(ApexRadius_lg),
              onTap: item.status == 'DRAFT'
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SalesOrderFormScreen(editId: item.id),
                      ),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.soNumber,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        MonetaryText(
                          value: fmt.currency(item.total),
                          fontWeight: FontWeight.w800,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Order actions',
                          onSelected: (value) => onWorkflow(item, value),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'print',
                              child: Text('Download PDF'),
                            ),
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
                    const SizedBox(height: 6),
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
                        'Required by ${item.dueDate}',
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
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return InkWell(
                    onTap: item.status == 'DRAFT'
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SalesOrderFormScreen(editId: item.id),
                            ),
                          )
                        : null,
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
                          PopupMenuButton<String>(
                            tooltip: 'Workflow actions',
                            onSelected: (value) => onWorkflow(item, value),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'print',
                                child: Text('Download PDF'),
                              ),
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
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(ApexRadius_md),
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
                      borderRadius: BorderRadius.circular(ApexRadius_sm),
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
